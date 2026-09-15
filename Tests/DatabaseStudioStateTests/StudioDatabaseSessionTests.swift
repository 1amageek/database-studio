import Foundation
import Testing
import DatabaseKit
@testable import DatabaseStudioUI

private enum ConnectionProbeFailure: Error, Sendable {
    case load
}

private actor ConnectionResourceProbe {
    private(set) var createdCount = 0
    private(set) var shutdownRequestCount = 0
    private(set) var shutdownCompletionCount = 0
    private var isShutdownReleased = false
    private var releaseLoad = true
    private var releaseFirstLoad = true
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstLoadWaiters: [CheckedContinuation<Void, Never>] = []
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []

    func makeResource(failing: Bool = false) -> StudioConnectionResource {
        createdCount += 1
        let resourceID = createdCount
        let staleEntity = try! Schema.Entity(
            name: "stale-(resourceID)",
            identifierType: .string,
            fields: [
                FieldSchema(
                    name: "value",
                    fieldNumber: 1,
                    type: .string
                )
            ]
        )
        return StudioConnectionResource(
            loadEntities: { [self] in
                await waitForLoadRelease()
                if failing {
                    throw ConnectionProbeFailure.load
                }
                if resourceID == 1 {
                    await waitForFirstLoadRelease()
                    return [staleEntity]
                }
                return []
            },
            loadOntology: { nil },
            requestShutdown: { [self] in
                Task { await recordShutdownRequest() }
            },
            waitUntilShutdown: { [self] in
                await waitForShutdownRelease()
                await recordShutdownCompletion()
            }
        )
    }

    func releaseLoading() {
        releaseLoad = true
        let waiters = loadWaiters
        loadWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func holdLoading() {
        releaseLoad = false
    }

    func holdFirstLoading() {
        releaseFirstLoad = false
    }

    func releaseFirstLoading() {
        releaseFirstLoad = true
        let waiters = firstLoadWaiters
        firstLoadWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func releaseShutdown() {
        isShutdownReleased = true
        let waiters = shutdownWaiters
        shutdownWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForCreatedCount(_ expected: Int) async {
        while createdCount < expected {
            await Task.yield()
        }
    }

    func waitForShutdownRequest() async {
        while shutdownRequestCount == 0 {
            await Task.yield()
        }
    }

    func waitForLoadRelease() async {
        guard !releaseLoad else { return }
        await withCheckedContinuation { continuation in
            if releaseLoad {
                continuation.resume()
            } else {
                loadWaiters.append(continuation)
            }
        }
    }

    func waitForFirstLoadRelease() async {
        guard !releaseFirstLoad else { return }
        await withCheckedContinuation { continuation in
            if releaseFirstLoad {
                continuation.resume()
            } else {
                firstLoadWaiters.append(continuation)
            }
        }
    }

    func waitForShutdownRelease() async {
        guard !isShutdownReleased else { return }
        await withCheckedContinuation { continuation in
            if isShutdownReleased {
                continuation.resume()
            } else {
                shutdownWaiters.append(continuation)
            }
        }
    }

    private func recordShutdownRequest() {
        shutdownRequestCount += 1
    }

    private func recordShutdownCompletion() {
        shutdownCompletionCount += 1
    }
}

@MainActor
@Suite("Studio Database Session Guard Behavior")
struct StudioDatabaseSessionTests {
    @Test("Disconnected is published only after shutdown completes", .timeLimit(.minutes(1)))
    func disconnectedWaitsForShutdown() async {
        let probe = ConnectionResourceProbe()
        let session = StudioDatabaseSession { _, _ in
            await probe.makeResource()
        }

        await session.connect(filePath: "first.sqlite")
        let disconnectTask = Task { @MainActor in
            await session.disconnect()
        }

        await probe.waitForShutdownRequest()
        #expect(session.connectionState == .disconnecting)
        let completionBeforeRelease = await probe.shutdownCompletionCount
        #expect(completionBeforeRelease == 0)

        await probe.releaseShutdown()
        await disconnectTask.value
        #expect(session.connectionState == .disconnected)
        let completionAfterRelease = await probe.shutdownCompletionCount
        #expect(completionAfterRelease == 1)
    }

    @Test("Reconnect waits for the previous resource to finish shutdown", .timeLimit(.minutes(1)))
    func reconnectWaitsForPreviousShutdown() async {
        let probe = ConnectionResourceProbe()
        let session = StudioDatabaseSession { _, _ in
            await probe.makeResource()
        }

        await session.connect(filePath: "first.sqlite")
        let disconnectTask = Task { @MainActor in
            await session.disconnect()
        }
        await probe.waitForShutdownRequest()

        let reconnectTask = Task { @MainActor in
            await session.connect(filePath: "second.sqlite")
        }
        await Task.yield()
        #expect(await probe.createdCount == 1)

        await probe.releaseShutdown()
        await disconnectTask.value
        await reconnectTask.value
        #expect(await probe.createdCount == 2)
        #expect(session.connectionState == .connected)

        await session.disconnect()
        await probe.releaseShutdown()
    }

    @Test("Cancelling a loading connection waits for its resource cleanup", .timeLimit(.minutes(1)))
    func cancellationWaitsForResourceCleanup() async {
        let probe = ConnectionResourceProbe()
        await probe.holdLoading()
        let session = StudioDatabaseSession { _, _ in
            await probe.makeResource()
        }

        let connectTask = Task { @MainActor in
            await session.connect(filePath: "loading.sqlite")
        }
        await probe.waitForCreatedCount(1)
        let cancelTask = Task { @MainActor in
            await session.cancelConnectionAttempt()
        }
        await probe.waitForShutdownRequest()
        #expect(session.connectionState == .disconnecting)
        let shutdownRequests = await probe.shutdownRequestCount
        #expect(shutdownRequests == 1)

        await probe.releaseLoading()
        await probe.releaseShutdown()
        await cancelTask.value
        await connectTask.value
        #expect(session.connectionState == .disconnected)
        let completionCount = await probe.shutdownCompletionCount
        #expect(completionCount == 1)
    }

    @Test("A failed connection reports its error only after cleanup", .timeLimit(.minutes(1)))
    func failedConnectionWaitsForResourceCleanup() async {
        let probe = ConnectionResourceProbe()
        let session = StudioDatabaseSession { _, _ in
            await probe.makeResource(failing: true)
        }

        let connectTask = Task { @MainActor in
            await session.connect(filePath: "failed.sqlite")
        }
        await probe.waitForCreatedCount(1)
        await probe.waitForShutdownRequest()
        #expect(session.connectionState == .disconnecting)
        let completionBeforeRelease = await probe.shutdownCompletionCount
        #expect(completionBeforeRelease == 0)

        await probe.releaseShutdown()
        await connectTask.value
        guard case .error(let message) = session.connectionState else {
            Issue.record("Expected a connection error after cleanup")
            return
        }
        #expect(!message.isEmpty)
        let completionAfterRelease = await probe.shutdownCompletionCount
        #expect(completionAfterRelease == 1)
    }

    @Test("A superseded load cannot publish stale entities", .timeLimit(.minutes(1)))
    func supersededLoadCannotPublishStaleEntities() async {
        let probe = ConnectionResourceProbe()
        await probe.holdFirstLoading()
        let session = StudioDatabaseSession { _, _ in
            await probe.makeResource()
        }

        let firstConnect = Task { @MainActor in
            await session.connect(filePath: "first.sqlite")
        }
        await probe.waitForCreatedCount(1)

        let secondConnect = Task { @MainActor in
            await session.connect(filePath: "second.sqlite")
        }
        await Task.yield()
        #expect(await probe.createdCount == 1)

        await probe.releaseFirstLoading()
        await probe.releaseShutdown()
        await firstConnect.value
        await secondConnect.value

        #expect(session.connectionState == .connected)
        #expect(session.entities.isEmpty)
        await session.disconnect()
    }

    @Test("Record listing fails while disconnected")
    func recordListingFailsWhileDisconnected() async {
        let session = StudioDatabaseSession()
        await expectNotConnected {
            _ = try await session.records(typeName: "Test")
        }
    }

    @Test("Record lookup fails while disconnected")
    func recordLookupFailsWhileDisconnected() async {
        let session = StudioDatabaseSession()
        await expectNotConnected {
            _ = try await session.record(typeName: "Test", id: "1")
        }
    }

    @Test("Record write fails while disconnected")
    func recordWriteFailsWhileDisconnected() async {
        let session = StudioDatabaseSession()
        await expectNotConnected {
            try await session.writeRecord(
                typeName: "Test",
                fields: ["id": "1"]
            )
        }
    }

    @Test("Record deletion fails while disconnected")
    func recordDeletionFailsWhileDisconnected() async {
        let session = StudioDatabaseSession()
        await expectNotConnected {
            try await session.deleteRecord(typeName: "Test", id: "1")
        }
    }

    @Test("Collection statistics fail while disconnected")
    func collectionStatisticsFailWhileDisconnected() async {
        let session = StudioDatabaseSession()
        await expectNotConnected {
            _ = try await session.collectionStatistics(typeName: "Test")
        }
    }

    @Test("Schema loading fails while disconnected")
    func schemaLoadingFailsWhileDisconnected() async {
        let session = StudioDatabaseSession()
        await expectNotConnected {
            try await session.loadEntities()
        }
    }

    @Test("Ontology loading fails while disconnected")
    func ontologyLoadingFailsWhileDisconnected() async {
        let session = StudioDatabaseSession()
        await expectNotConnected {
            _ = try await session.loadOntology()
        }
    }

    @Test("Disconnect is idempotent")
    func disconnectIsIdempotent() async {
        let session = StudioDatabaseSession()
        await session.disconnect()
        await session.disconnect()
        #expect(session.connectionState == .disconnected)
    }

    @Test("A new session is disconnected")
    func newSessionIsDisconnected() {
        let session = StudioDatabaseSession()
        #expect(session.connectionState == .disconnected)
        #expect(session.entities.isEmpty)
    }

    @Test("An empty SQLite database is rejected without a format descriptor")
    func emptySQLiteDatabaseIsRejectedWithoutFormatDescriptor() async throws {
        let session = StudioDatabaseSession()
        let databasePath = "/tmp/database-studio-session-\(UUID()).sqlite"

        await session.connect(filePath: databasePath)

        guard case .error(let message) = session.connectionState else {
            Issue.record("Expected a canonical format validation failure")
            if FileManager.default.fileExists(atPath: databasePath) {
                try FileManager.default.removeItem(atPath: databasePath)
            }
            return
        }
        #expect(!message.isEmpty)
        #expect(session.entities.isEmpty)
        await expectNotConnected {
            _ = try await session.records(typeName: "Test")
        }

        if FileManager.default.fileExists(atPath: databasePath) {
            try FileManager.default.removeItem(atPath: databasePath)
        }
    }

    private func expectNotConnected(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected StudioError.notConnected")
        } catch StudioError.notConnected {
            return
        } catch {
            Issue.record("Expected StudioError.notConnected, received \(error)")
        }
    }
}
