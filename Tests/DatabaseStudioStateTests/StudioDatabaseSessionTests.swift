import Foundation
import Testing
@testable import DatabaseStudioUI

@MainActor
@Suite("Studio Database Session Guard Behavior")
struct StudioDatabaseSessionTests {
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
    func disconnectIsIdempotent() {
        let session = StudioDatabaseSession()
        session.disconnect()
        session.disconnect()
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
