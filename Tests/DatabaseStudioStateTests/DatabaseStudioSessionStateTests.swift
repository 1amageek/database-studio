import Testing
import Foundation
@testable import DatabaseStudioUI
import Core

@MainActor
@Suite("Session State Management")
struct DatabaseStudioSessionStateTests {

    // MARK: - disconnect() completeness

    @Test("disconnect resets all session state to defaults")
    func disconnectResetsAllState() {
        let studioState = DatabaseStudioState()

        // Set every session state property to a non-default value.
        // If a new session property is added but not reset in resetSessionState(),
        // this test MUST be updated — and will fail if forgotten.
        studioState.selectedEntityName = "SomeEntity"
        studioState.selectedIndexName = "SomeIndex"
        studioState.selectedItemID = "item_1"
        studioState.selectedItemIDs = ["item_1", "item_2"]
        studioState.entityTree = [EntityTreeNode(name: "test", path: ["test"])]
        studioState.currentItems = [StudioRecord(id: "1", typeName: "T", fields: [:], jsonByteCount: 10)]
        studioState.currentCollectionStats = CollectionStats(typeName: "T", documentCount: 5, storageSize: 100)
        studioState.databaseOperationFailureMessage = "stale failure"
        studioState.currentItemPage = StudioRecordPage(
            items: [StudioRecord(id: "1", typeName: "T", fields: [:], jsonByteCount: 10)],
            hasMore: true,
            offset: 0,
            limit: 100
        )
        studioState.currentQuery = ItemQuery(rootGroup: QueryConditionGroup(
            conditions: [QueryCondition(fieldPath: "name", operator: .equal, value: .string("test"))]
        ))
        studioState.discoveredFields = [DiscoveredField(path: "name", name: "name", inferredType: .string, sampleValues: [], depth: 0)]

        studioState.disconnect()

        // Navigation
        #expect(studioState.selectedEntityName == nil)
        #expect(studioState.selectedIndexName == nil)
        #expect(studioState.selectedItemID == nil)
        #expect(studioState.selectedItemIDs.isEmpty)

        // Data
        #expect(studioState.entityTree.isEmpty)
        #expect(studioState.currentItems.isEmpty)
        #expect(studioState.currentCollectionStats == nil)
        #expect(studioState.currentItemPage == nil)
        #expect(studioState.databaseOperationFailureMessage == nil)

        // Query
        #expect(studioState.currentQuery.conditionCount == 0)
        #expect(studioState.discoveredFields.isEmpty)

        // Loading indicators
        #expect(studioState.isLoadingEntities == false)
        #expect(studioState.isLoadingItems == false)
        #expect(studioState.isLoadingStats == false)
        #expect(studioState.isLoadingMoreItems == false)

        // Computed properties
        #expect(studioState.hasMoreItems == false)
    }

    // MARK: - connect() resets state

    @Test("connect resets stale session state before connecting")
    func connectResetsStaleState() async throws {
        let studioState = DatabaseStudioState()

        // Simulate stale state from a previous connection
        studioState.selectedEntityName = "OldEntity"
        studioState.selectedIndexName = "OldIndex"
        studioState.selectedItemID = "old_item"
        studioState.selectedItemIDs = ["old_1", "old_2"]
        studioState.entityTree = [EntityTreeNode(name: "old", path: ["old"])]
        studioState.currentItems = [StudioRecord(id: "old", typeName: "Old", fields: [:], jsonByteCount: 10)]
        studioState.currentCollectionStats = CollectionStats(typeName: "Old", documentCount: 100, storageSize: 5000)
        studioState.databaseOperationFailureMessage = "stale failure"

        // Connect to a new (empty) SQLite database
        let databasePath = "/tmp/test-session-\(UUID()).sqlite"
        studioState.filePath = databasePath
        await studioState.connect()

        // All stale state must be cleared
        #expect(studioState.selectedEntityName == nil)
        #expect(studioState.selectedIndexName == nil)
        #expect(studioState.selectedItemID == nil)
        #expect(studioState.selectedItemIDs.isEmpty)
        #expect(studioState.currentCollectionStats == nil)
        #expect(studioState.currentQuery.conditionCount == 0)
        #expect(studioState.discoveredFields.isEmpty)
        #expect(studioState.databaseOperationFailureMessage == nil)

        // Clean up
        studioState.disconnect()
        if FileManager.default.fileExists(atPath: databasePath) {
            try FileManager.default.removeItem(atPath: databasePath)
        }
    }

    // MARK: - Idempotency

    @Test("disconnect is idempotent")
    func disconnectIsIdempotent() {
        let studioState = DatabaseStudioState()
        studioState.disconnect()
        studioState.disconnect()
        #expect(studioState.connectionState == .disconnected)
    }

    // MARK: - Configuration state preservation

    @Test("disconnect preserves configuration state")
    func disconnectPreservesConfiguration() {
        let studioState = DatabaseStudioState()
        studioState.filePath = "/custom/path.sqlite"
        studioState.rootDirectoryPath = "myapp"
        studioState.pageSize = 50

        studioState.disconnect()

        #expect(studioState.filePath == "/custom/path.sqlite")
        #expect(studioState.rootDirectoryPath == "myapp")
        #expect(studioState.pageSize == 50)
    }

    // MARK: - Computed properties after reset

    @Test("computed properties reflect reset state")
    func computedPropertiesReflectResetState() {
        let studioState = DatabaseStudioState()
        studioState.selectedItemID = "x"
        studioState.selectedItemIDs = ["x", "y"]
        studioState.currentItems = [StudioRecord(id: "x", typeName: "T", fields: [:], jsonByteCount: 0)]

        studioState.disconnect()

        #expect(studioState.selectedItem == nil)
        #expect(studioState.selectedItems.isEmpty)
        #expect(studioState.selectedEntity == nil)
        #expect(studioState.hasMoreItems == false)
    }
}
