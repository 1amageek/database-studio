import SwiftUI
import Observation
import Core
import Graph

/// アプリケーション全体のViewModel
@MainActor
@Observable
public final class AppViewModel {
    // MARK: - Data Service

    @ObservationIgnored
    public let dataService = StudioDataService()

    @ObservationIgnored
    public let metricsService: MetricsService = MetricsService()

    // MARK: - Connection

    public var clusterFilePath: String = "/etc/foundationdb/fdb.cluster"
    public var rootDirectoryPath: String = ""

    public var connectionState: StudioDataService.ConnectionState {
        dataService.connectionState
    }

    // MARK: - Navigation State

    public var selectedEntityName: String?
    public var selectedIndexName: String?

    /// 選択されている Schema.Entity
    public var selectedEntity: Schema.Entity? {
        guard let name = selectedEntityName else { return nil }
        return dataService.entity(for: name)
    }

    // MARK: - Data

    public internal(set) var entityTree: [EntityTreeNode] = []
    public internal(set) var currentItems: [DecodedItem] = []
    public var selectedItemID: String?
    public var selectedItemIDs: Set<String> = []

    /// 選択されている複数アイテム
    public var selectedItems: [DecodedItem] {
        currentItems.filter { selectedItemIDs.contains($0.id) }
    }

    // MARK: - Pagination State

    @ObservationIgnored
    public internal(set) var currentItemPage: DecodedItemPage?
    public var pageSize: Int = 100

    public var currentOffset: Int {
        currentItemPage?.offset ?? 0
    }

    public var hasMoreItems: Bool {
        currentItemPage?.hasMore ?? false
    }

    public var hasPreviousPage: Bool {
        currentOffset > 0
    }

    public var pageInfoText: String {
        guard let page = currentItemPage, !currentItems.isEmpty else {
            return ""
        }
        let start = page.offset + 1
        let end = page.offset + currentItems.count
        return "Items \(start)-\(end)"
    }

    // MARK: - Query State

    public var currentQuery: ItemQuery = ItemQuery()
    public internal(set) var discoveredFields: [DiscoveredField] = []

    /// 選択されているItem
    public var selectedItem: DecodedItem? {
        guard let id = selectedItemID else { return nil }
        return currentItems.first { $0.id == id }
    }

    // MARK: - Statistics

    public internal(set) var currentCollectionStats: CollectionStats?

    // MARK: - Loading State

    public private(set) var isLoadingEntities = false
    public private(set) var isLoadingItems = false
    public private(set) var isLoadingStats = false

    // MARK: - Operation Tracking

    @ObservationIgnored
    private var currentItemsLoadID: UUID?

    public init() {}

    // MARK: - Connection

    public func connect() async {
        await dataService.connect(clusterFilePath: clusterFilePath)
        if case .connected = dataService.connectionState {
            buildEntityTree()
        }
    }

    public func disconnect() {
        dataService.disconnect()
        entityTree = []
        currentItems = []
        currentCollectionStats = nil
        selectedEntityName = nil
        selectedItemID = nil
        selectedIndexName = nil
    }

    // MARK: - Entity Tree

    public func buildEntityTree() {
        let entities = dataService.entities
        var roots: [String: EntityTreeNode] = [:]

        for entity in entities {
            let components = entity.directoryComponents.compactMap { component -> String? in
                if case .staticPath(let path) = component {
                    return path
                }
                return nil
            }

            guard !components.isEmpty else {
                // ルートレベルのエンティティ
                let rootName = "_root"
                if roots[rootName] == nil {
                    roots[rootName] = EntityTreeNode(name: "Root", path: [])
                }
                roots[rootName]?.entities.append(entity)
                continue
            }

            let rootName = components[0]
            if roots[rootName] == nil {
                roots[rootName] = EntityTreeNode(name: rootName, path: [rootName])
            }

            if components.count == 1 {
                roots[rootName]?.entities.append(entity)
            } else {
                // ネストされたパス
                var currentNode = roots[rootName]!
                for i in 1..<components.count {
                    let childName = components[i]
                    let childPath = Array(components[0...i])
                    if let existingIndex = currentNode.children.firstIndex(where: { $0.name == childName }) {
                        if i == components.count - 1 {
                            currentNode.children[existingIndex].entities.append(entity)
                        }
                    } else {
                        var child = EntityTreeNode(name: childName, path: childPath)
                        if i == components.count - 1 {
                            child.entities.append(entity)
                        }
                        currentNode.children.append(child)
                    }
                }
                roots[rootName] = currentNode
            }
        }

        entityTree = roots.values.sorted { $0.name < $1.name }
    }

    public func refreshEntities() async {
        isLoadingEntities = true
        defer { isLoadingEntities = false }

        do {
            try await dataService.loadEntities()
            buildEntityTree()
        } catch {
            print("Failed to refresh entities: \(error)")
        }
    }

    // MARK: - Entity Selection

    public func selectEntity(_ entityName: String) {
        Task {
            await selectEntityAsync(entityName)
        }
    }

    private func selectEntityAsync(_ entityName: String) async {
        let previousName = selectedEntityName
        selectedEntityName = entityName
        selectedIndexName = nil
        selectedItemID = nil
        currentQuery = ItemQuery()

        if entityName != previousName {
            await loadItems(for: entityName)
            await loadCollectionStats(for: entityName)
        }
    }

    // MARK: - Items

    public func loadItems(for entityName: String, offset: Int = 0) async {
        if isPreviewMode {
            loadPreviewItems(for: entityName)
            updateDiscoveredFields()
            return
        }

        let operationID = UUID()
        currentItemsLoadID = operationID

        isLoadingItems = true

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let allItems = try await dataService.findAll(typeName: entityName, limit: pageSize + 1)

            guard currentItemsLoadID == operationID else { return }

            let hasMore = allItems.count > pageSize
            let pageItems = hasMore ? Array(allItems.prefix(pageSize)) : allItems

            let decodedItems = pageItems.enumerated().map { index, dict -> DecodedItem in
                let id = dict["id"] as? String ?? "item_\(offset + index)"
                let data = (try? JSONSerialization.data(withJSONObject: dict, options: [])) ?? Data()
                return DecodedItem(
                    id: id,
                    typeName: entityName,
                    fields: dict,
                    rawSize: data.count
                )
            }

            currentItemPage = DecodedItemPage(
                items: decodedItems,
                hasMore: hasMore,
                offset: offset,
                limit: pageSize
            )
            currentItems = decodedItems
            updateDiscoveredFields()

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordSuccess(duration: duration, description: "Load items: \(entityName)", typeName: entityName, operationType: .read)
        } catch {
            guard currentItemsLoadID == operationID else { return }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordFailure(duration: duration, description: "Load items: \(entityName)", typeName: entityName, operationType: .read)
            print("Failed to load items: \(error)")
            currentItemPage = nil
            currentItems = []
        }

        isLoadingItems = false
    }

    /// グラフ表示用に全件ロードする（ページングなし）
    public func loadAllItems(for entityName: String) async -> [DecodedItem] {
        if isPreviewMode {
            return currentItems
        }
        do {
            let allItems = try await dataService.findAll(typeName: entityName)
            return allItems.enumerated().map { index, dict -> DecodedItem in
                let id = dict["id"] as? String ?? "item_\(index)"
                let data = (try? JSONSerialization.data(withJSONObject: dict, options: [])) ?? Data()
                return DecodedItem(
                    id: id,
                    typeName: entityName,
                    fields: dict,
                    rawSize: data.count
                )
            }
        } catch {
            print("Failed to load all items for graph: \(error)")
            return []
        }
    }

    /// OntologyStore から OWLOntology をロードする
    public func loadOntology() async -> OWLOntology? {
        if isPreviewMode { return nil }
        do {
            let ontology = try await dataService.loadOntology()
            if let ontology {
                print("[Ontology] Loaded: \(ontology.classes.count) classes, \(ontology.axioms.count) axioms")
            }
            return ontology
        } catch {
            print("[Ontology] Failed to load: \(error)")
            return nil
        }
    }

    public func loadNextPage() async {
        guard hasMoreItems,
              let entityName = selectedEntityName,
              let nextOffset = currentItemPage?.nextOffset else { return }
        await loadItems(for: entityName, offset: nextOffset)
    }

    public func loadPreviousPage() async {
        guard hasPreviousPage,
              let entityName = selectedEntityName else { return }
        let prevOffset = max(0, currentOffset - pageSize)
        await loadItems(for: entityName, offset: prevOffset)
    }

    public func changePageSize(_ newSize: Int) async {
        pageSize = newSize
        guard let entityName = selectedEntityName else { return }
        await loadItems(for: entityName, offset: 0)
    }

    public func selectItem(id: String?) {
        selectedItemID = id
    }

    public func selectItems(ids: Set<String>) {
        selectedItemIDs = ids
        selectedItemID = ids.first
    }

    public func clearSelection() {
        selectedItemIDs.removeAll()
        selectedItemID = nil
    }

    // MARK: - Query

    public func updateDiscoveredFields() {
        discoveredFields = FieldDiscovery.discoverFields(from: currentItems)
    }

    public func clearQuery() {
        currentQuery = ItemQuery()
    }

    // MARK: - Statistics

    public func loadCollectionStats(for entityName: String) async {
        isLoadingStats = true
        defer { isLoadingStats = false }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            currentCollectionStats = try await dataService.collectionStats(typeName: entityName)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordSuccess(duration: duration, description: "Load stats: \(entityName)", typeName: entityName, operationType: .read)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordFailure(duration: duration, description: "Load stats: \(entityName)", typeName: entityName, operationType: .read)
            print("Failed to load collection stats: \(error)")
            currentCollectionStats = nil
        }
    }

    // MARK: - CRUD Operations

    public func createItem(id: String, json: [String: Any]) async throws {
        guard let entityName = selectedEntityName else {
            throw StudioError.noTypeSelected
        }

        var mutableJson = json
        mutableJson["id"] = id

        let jsonData = try JSONSerialization.data(withJSONObject: mutableJson, options: [])
        guard let sendableJson = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            throw StudioError.invalidJSON("Failed to convert JSON")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            try await dataService.insertItem(typeName: entityName, dict: sendableJson)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordSuccess(duration: duration, description: "Create item: \(id)", typeName: entityName, operationType: .write)
            await loadItems(for: entityName)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordFailure(duration: duration, description: "Create item: \(id)", typeName: entityName, operationType: .write)
            throw error
        }
    }

    public func updateItem(id: String, json: [String: Any]) async throws {
        guard let entityName = selectedEntityName else {
            throw StudioError.noTypeSelected
        }

        var mutableJson = json
        mutableJson["id"] = id

        let jsonData = try JSONSerialization.data(withJSONObject: mutableJson, options: [])
        guard let sendableJson = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            throw StudioError.invalidJSON("Failed to convert JSON")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            try await dataService.insertItem(typeName: entityName, dict: sendableJson)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordSuccess(duration: duration, description: "Update item: \(id)", typeName: entityName, operationType: .write)
            await loadItems(for: entityName, offset: currentOffset)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordFailure(duration: duration, description: "Update item: \(id)", typeName: entityName, operationType: .write)
            throw error
        }
    }

    public func deleteItem(id: String) async throws {
        guard let entityName = selectedEntityName else {
            throw StudioError.noTypeSelected
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            try await dataService.deleteItem(typeName: entityName, id: id)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordSuccess(duration: duration, description: "Delete item: \(id)", typeName: entityName, operationType: .write)
            if selectedItemID == id {
                selectedItemID = nil
            }
            selectedItemIDs.remove(id)
            await loadItems(for: entityName, offset: currentOffset)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordFailure(duration: duration, description: "Delete item: \(id)", typeName: entityName, operationType: .write)
            throw error
        }
    }

    public func deleteItems(ids: [String]) async throws {
        guard let entityName = selectedEntityName else {
            throw StudioError.noTypeSelected
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            for id in ids {
                try await dataService.deleteItem(typeName: entityName, id: id)
            }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordSuccess(duration: duration, description: "Delete \(ids.count) items", typeName: entityName, operationType: .write)
            for id in ids {
                selectedItemIDs.remove(id)
            }
            if let selectedID = selectedItemID, ids.contains(selectedID) {
                selectedItemID = nil
            }
            await loadItems(for: entityName, offset: currentOffset)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordFailure(duration: duration, description: "Delete \(ids.count) items", typeName: entityName, operationType: .write)
            throw error
        }
    }

    public func importItems(records: [[String: Any]]) async throws -> Int {
        guard let entityName = selectedEntityName else {
            throw StudioError.noTypeSelected
        }

        let jsonData = try JSONSerialization.data(withJSONObject: records, options: [])
        guard let sendableRecords = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] else {
            throw StudioError.invalidJSON("Failed to convert records")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            var count = 0
            for record in sendableRecords {
                try await dataService.insertItem(typeName: entityName, dict: record)
                count += 1
            }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordSuccess(duration: duration, description: "Import \(count) items", typeName: entityName, operationType: .write)
            await loadItems(for: entityName, offset: 0)
            return count
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsService.recordFailure(duration: duration, description: "Import items", typeName: entityName, operationType: .write)
            throw error
        }
    }

    // MARK: - Preview Support

    @ObservationIgnored
    private var isPreviewMode = false

    @ObservationIgnored
    private var previewItemsProvider: (@MainActor (String) -> [DecodedItem])?

    public static func preview(
        connectionState: StudioDataService.ConnectionState = .connected,
        entityTree: [EntityTreeNode] = [],
        entities: [Schema.Entity] = [],
        selectedEntityName: String? = nil,
        items: [DecodedItem] = [],
        selectedItemID: String? = nil,
        itemsProvider: (@MainActor (String) -> [DecodedItem])? = nil,
        collectionStats: CollectionStats? = nil
    ) -> AppViewModel {
        let vm = AppViewModel()
        vm.isPreviewMode = true
        vm.previewItemsProvider = itemsProvider
        vm.entityTree = entityTree
        vm.currentItems = items
        vm.selectedItemID = selectedItemID
        vm.currentCollectionStats = collectionStats
        vm.selectedEntityName = selectedEntityName
        return vm
    }

    private func loadPreviewItems(for entityName: String) {
        if let provider = previewItemsProvider {
            currentItems = provider(entityName)
        }
    }
}

// MARK: - Errors

public enum StudioError: Error, LocalizedError {
    case noTypeSelected
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .noTypeSelected: return "No type selected"
        case .invalidJSON(let msg): return msg
        }
    }
}
