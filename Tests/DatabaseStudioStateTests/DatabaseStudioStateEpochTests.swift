import Foundation
import Testing
import DatabaseKit
@testable import DatabaseStudioUI

/// Holds the second entity load of the first resource so a reconnect can supersede it.
private actor SupersededLoadProbe {
    private var createdCount = 0
    private var firstResourceLoads = 0
    private var isHeldLoadEntered = false
    private var heldLoad: CheckedContinuation<Void, Never>?

    func makeResource() -> StudioConnectionResource {
        createdCount += 1
        let resourceID = createdCount
        let entity = try! Schema.Entity(
            name: "resource-\(resourceID)",
            identifierType: .string,
            fields: [FieldSchema(name: "value", fieldNumber: 1, type: .string)]
        )
        return StudioConnectionResource(
            loadEntities: { [self] in
                if resourceID == 1 { await holdSecondLoad() }
                return [entity]
            },
            loadOntology: { nil },
            requestShutdown: {},
            waitUntilShutdown: {}
        )
    }

    private func holdSecondLoad() async {
        firstResourceLoads += 1
        guard firstResourceLoads == 2 else { return }
        await withCheckedContinuation { continuation in
            isHeldLoadEntered = true
            heldLoad = continuation
        }
    }

    func waitUntilHeldLoadEntered() async {
        while !isHeldLoadEntered { await Task.yield() }
    }

    func releaseHeldLoad() {
        heldLoad?.resume()
        heldLoad = nil
    }
}

@MainActor
@Suite("Database Studio State Connection Epoch")
struct DatabaseStudioStateEpochTests {
    @Test("A refresh superseded by reconnect publishes neither its error nor its loading state", .timeLimit(.minutes(1)))
    func supersededRefreshDoesNotPublish() async {
        let probe = SupersededLoadProbe()
        let state = DatabaseStudioState(databaseSession: StudioDatabaseSession { _, _ in
            await probe.makeResource()
        })
        await state.connect()
        #expect(state.entityTree.flatMap(\.entities).map(\.name) == ["resource-1"])

        let refresh = Task { @MainActor in await state.refreshEntities() }
        await probe.waitUntilHeldLoadEntered()
        #expect(state.isLoadingEntities)

        await state.connect()
        #expect(state.entityTree.flatMap(\.entities).map(\.name) == ["resource-2"])
        #expect(!state.isLoadingEntities)

        await probe.releaseHeldLoad()
        await refresh.value
        #expect(state.databaseOperationFailureMessage == nil)
        #expect(state.entityTree.flatMap(\.entities).map(\.name) == ["resource-2"])
        #expect(!state.isLoadingEntities)
        await state.disconnect()
    }

    @Test("A current refresh still reports its own failure", .timeLimit(.minutes(1)))
    func currentRefreshFailureIsPublished() async {
        let state = DatabaseStudioState(databaseSession: StudioDatabaseSession { _, _ in
            StudioConnectionResource(loadEntities: { [] }, loadOntology: { nil },
                                     requestShutdown: {}, waitUntilShutdown: {})
        })
        await state.refreshEntities()
        #expect(state.databaseOperationFailureMessage != nil)
        #expect(!state.isLoadingEntities)
    }
}
