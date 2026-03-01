import Testing
import Foundation
@testable import DatabaseStudioUI
import Core

@MainActor
@Suite("Session State Management")
struct SessionStateTests {

    // MARK: - disconnect() completeness

    @Test("disconnect resets all session state to defaults")
    func disconnectResetsAllState() {
        let vm = AppViewModel()

        // Set every session state property to a non-default value.
        // If a new session property is added but not reset in resetSessionState(),
        // this test MUST be updated — and will fail if forgotten.
        vm.selectedEntityName = "SomeEntity"
        vm.selectedIndexName = "SomeIndex"
        vm.selectedItemID = "item_1"
        vm.selectedItemIDs = ["item_1", "item_2"]
        vm.entityTree = [EntityTreeNode(name: "test", path: ["test"])]
        vm.currentItems = [DecodedItem(id: "1", typeName: "T", fields: [:], rawSize: 10)]
        vm.currentCollectionStats = CollectionStats(typeName: "T", documentCount: 5, storageSize: 100)
        vm.currentItemPage = DecodedItemPage(
            items: [DecodedItem(id: "1", typeName: "T", fields: [:], rawSize: 10)],
            hasMore: true,
            offset: 0,
            limit: 100
        )
        vm.currentQuery = ItemQuery(rootGroup: QueryConditionGroup(
            conditions: [QueryCondition(fieldPath: "name", operator: .equal, value: .string("test"))]
        ))
        vm.discoveredFields = [DiscoveredField(path: "name", name: "name", inferredType: .string, sampleValues: [], depth: 0)]

        vm.disconnect()

        // Navigation
        #expect(vm.selectedEntityName == nil)
        #expect(vm.selectedIndexName == nil)
        #expect(vm.selectedItemID == nil)
        #expect(vm.selectedItemIDs.isEmpty)

        // Data
        #expect(vm.entityTree.isEmpty)
        #expect(vm.currentItems.isEmpty)
        #expect(vm.currentCollectionStats == nil)
        #expect(vm.currentItemPage == nil)

        // Query
        #expect(vm.currentQuery.conditionCount == 0)
        #expect(vm.discoveredFields.isEmpty)

        // Loading indicators
        #expect(vm.isLoadingEntities == false)
        #expect(vm.isLoadingItems == false)
        #expect(vm.isLoadingStats == false)
        #expect(vm.isLoadingMoreItems == false)

        // Computed properties
        #expect(vm.hasMoreItems == false)
    }

    // MARK: - connect() resets state

    @Test("connect resets stale session state before connecting")
    func connectResetsStaleState() async {
        let vm = AppViewModel()

        // Simulate stale state from a previous connection
        vm.selectedEntityName = "OldEntity"
        vm.selectedIndexName = "OldIndex"
        vm.selectedItemID = "old_item"
        vm.selectedItemIDs = ["old_1", "old_2"]
        vm.entityTree = [EntityTreeNode(name: "old", path: ["old"])]
        vm.currentItems = [DecodedItem(id: "old", typeName: "Old", fields: [:], rawSize: 10)]
        vm.currentCollectionStats = CollectionStats(typeName: "Old", documentCount: 100, storageSize: 5000)

        // Connect to a new (empty) SQLite database
        let tmpPath = "/tmp/test-session-\(UUID()).sqlite"
        vm.filePath = tmpPath
        await vm.connect()

        // All stale state must be cleared
        #expect(vm.selectedEntityName == nil)
        #expect(vm.selectedIndexName == nil)
        #expect(vm.selectedItemID == nil)
        #expect(vm.selectedItemIDs.isEmpty)
        #expect(vm.currentCollectionStats == nil)
        #expect(vm.currentQuery.conditionCount == 0)
        #expect(vm.discoveredFields.isEmpty)

        // Clean up
        vm.disconnect()
        try? FileManager.default.removeItem(atPath: tmpPath)
    }

    // MARK: - Idempotency

    @Test("disconnect is idempotent")
    func disconnectIdempotent() {
        let vm = AppViewModel()
        vm.disconnect()
        vm.disconnect()
        #expect(vm.connectionState == .disconnected)
    }

    // MARK: - Configuration state preservation

    @Test("disconnect preserves configuration state")
    func disconnectPreservesConfig() {
        let vm = AppViewModel()
        vm.filePath = "/custom/path.sqlite"
        vm.rootDirectoryPath = "myapp"
        vm.pageSize = 50

        vm.disconnect()

        #expect(vm.filePath == "/custom/path.sqlite")
        #expect(vm.rootDirectoryPath == "myapp")
        #expect(vm.pageSize == 50)
    }

    // MARK: - Computed properties after reset

    @Test("computed properties reflect reset state")
    func computedPropertiesAfterReset() {
        let vm = AppViewModel()
        vm.selectedItemID = "x"
        vm.selectedItemIDs = ["x", "y"]
        vm.currentItems = [DecodedItem(id: "x", typeName: "T", fields: [:], rawSize: 0)]

        vm.disconnect()

        #expect(vm.selectedItem == nil)
        #expect(vm.selectedItems.isEmpty)
        #expect(vm.selectedEntity == nil)
        #expect(vm.hasMoreItems == false)
    }
}
