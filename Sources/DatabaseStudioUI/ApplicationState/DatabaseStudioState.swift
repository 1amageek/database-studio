import SwiftUI
import Observation
import DatabaseKit

/// Owns application-wide Database Studio state and database operations.
@MainActor
@Observable
public final class DatabaseStudioState {
    // MARK: - Database Dependencies

    @ObservationIgnored
    public let databaseSession = StudioDatabaseSession()

    @ObservationIgnored
    public let metricsRecorder: DatabaseMetricsRecorder = DatabaseMetricsRecorder()

    // MARK: - Configuration State (persists across connections)

    public var filePath: String = "/etc/foundationdb/fdb.cluster"
    public var rootDirectoryPath: String = ""
    public var pageSize: Int = 100

    public var connectionState: StudioDatabaseSession.ConnectionState {
        if let sampleConnectionState {
            return sampleConnectionState
        }
        return databaseSession.connectionState
    }

    public var connectionErrorPresentation: ConnectionErrorPresentation? {
        guard case .error(let message) = connectionState else { return nil }
        return Self.makeConnectionErrorPresentation(message: message)
    }

    // MARK: - Session State (reset on connect/disconnect)

    public internal(set) var entityTree: [EntityTreeNode] = []
    public internal(set) var currentItems: [StudioRecord] = []
    public var selectedItemID: String?
    public var selectedItemIDs: Set<String> = []
    public var selectedEntityName: String?
    public var selectedIndexName: String?

    @ObservationIgnored
    public internal(set) var currentItemPage: StudioRecordPage?

    public var currentQuery: ItemQuery = ItemQuery()
    public internal(set) var discoveredFields: [DiscoveredField] = []
    public internal(set) var currentCollectionStats: CollectionStats?
    public internal(set) var databaseOperationFailureMessage: String?

    public private(set) var isLoadingEntities = false
    public private(set) var isLoadingItems = false
    public private(set) var isLoadingStats = false
    public private(set) var isLoadingMoreItems = false

    @ObservationIgnored
    private var currentItemsLoadID: UUID?

    // MARK: - Computed Properties

    /// Selected Schema.Entity
    public var selectedEntity: Schema.Entity? {
        guard let name = selectedEntityName else { return nil }
        return databaseSession.entity(for: name)
    }

    /// Selected items (multi-selection)
    public var selectedItems: [StudioRecord] {
        currentItems.filter { selectedItemIDs.contains($0.id) }
    }

    public var hasMoreItems: Bool {
        currentItemPage?.hasMore ?? false
    }

    /// Selected item (single selection)
    public var selectedItem: StudioRecord? {
        guard let id = selectedItemID else { return nil }
        return currentItems.first { $0.id == id }
    }

    public init() {}

    // MARK: - Session State Management

    /// Single source of truth for resetting all session-bound state.
    ///
    /// Called by both `connect()` and `disconnect()`. Any new session state
    /// property added to this class MUST be reset here.
    private func resetSessionState() {
        selectedEntityName = nil
        selectedIndexName = nil
        selectedItemID = nil
        selectedItemIDs = []
        entityTree = []
        currentItems = []
        currentItemPage = nil
        currentCollectionStats = nil
        currentQuery = ItemQuery()
        discoveredFields = []
        databaseOperationFailureMessage = nil
        isLoadingEntities = false
        isLoadingItems = false
        isLoadingStats = false
        isLoadingMoreItems = false
        currentItemsLoadID = nil
    }

    // MARK: - Connection

    public func connect() async {
        resetSessionState()
        await databaseSession.connect(filePath: filePath)
        if case .connected = databaseSession.connectionState {
            buildEntityTree()
        }
    }

    public func disconnect() {
        databaseSession.disconnect()
        resetSessionState()
    }

    public func cancelConnectionAttempt() {
        databaseSession.cancelConnectionAttempt()
        resetSessionState()
    }

    // MARK: - Entity Tree

    public func buildEntityTree() {
        let entities = databaseSession.entities
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
        databaseOperationFailureMessage = nil
        defer { isLoadingEntities = false }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            try await databaseSession.loadEntities()
            buildEntityTree()
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordSuccess(duration: duration, description: "Refresh entities", operationType: .read)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordFailure(duration: duration, description: "Refresh entities", operationType: .read)
            databaseOperationFailureMessage = error.localizedDescription
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

    // MARK: - Record Presentation

    private func makeStudioRecords<Records: Collection>(
        from records: Records,
        typeName: String,
        offset: Int = 0
    ) throws -> [StudioRecord] where Records.Element == [String: Any] {
        var studioRecords: [StudioRecord] = []
        studioRecords.reserveCapacity(records.count)

        for (index, record) in records.enumerated() {
            guard let recordIdentifier = (record["id"] ?? record["_id"]) as? String else {
                throw StudioError.recordIdentifierMissing(position: offset + index)
            }

            do {
                let encodedRecord = try JSONSerialization.data(withJSONObject: record, options: [])
                studioRecords.append(
                    StudioRecord(
                        id: recordIdentifier,
                        typeName: typeName,
                        fields: record,
                        jsonByteCount: encodedRecord.count
                    )
                )
            } catch {
                throw StudioError.recordPresentationFailed(recordIdentifier, error.localizedDescription)
            }
        }

        return studioRecords
    }

    // MARK: - Items

    public func loadItems(for entityName: String, offset: Int = 0) async {
        if let sampleRecordsProvider {
            currentItems = sampleRecordsProvider(entityName)
            updateDiscoveredFields()
            return
        }

        let operationID = UUID()
        currentItemsLoadID = operationID

        isLoadingItems = true
        databaseOperationFailureMessage = nil

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let allItems = try await databaseSession.records(typeName: entityName, limit: pageSize + 1)

            guard currentItemsLoadID == operationID else { return }

            let hasMore = allItems.count > pageSize
            let pageRecords = allItems.prefix(pageSize)
            let studioRecords = try makeStudioRecords(from: pageRecords, typeName: entityName, offset: offset)

            currentItemPage = StudioRecordPage(
                items: studioRecords,
                hasMore: hasMore,
                offset: offset,
                limit: pageSize
            )
            currentItems = studioRecords
            updateDiscoveredFields()

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordSuccess(duration: duration, description: "Load items: \(entityName)", typeName: entityName, operationType: .read)
        } catch {
            guard currentItemsLoadID == operationID else { return }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordFailure(duration: duration, description: "Load items: \(entityName)", typeName: entityName, operationType: .read)
            currentItemPage = nil
            currentItems = []
            databaseOperationFailureMessage = error.localizedDescription
        }

        isLoadingItems = false
    }

    /// Load all items for graph display (no pagination).
    public func loadAllItems(for entityName: String) async throws -> [StudioRecord] {
        if let sampleRecordsProvider {
            return sampleRecordsProvider(entityName)
        }
        let startTime = CFAbsoluteTimeGetCurrent()
        databaseOperationFailureMessage = nil
        do {
            let allItems = try await databaseSession.records(typeName: entityName)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordSuccess(duration: duration, description: "Load all items: \(entityName)", typeName: entityName, operationType: .scan)
            return try makeStudioRecords(from: allItems, typeName: entityName)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordFailure(duration: duration, description: "Load all items: \(entityName)", typeName: entityName, operationType: .scan)
            databaseOperationFailureMessage = error.localizedDescription
            throw error
        }
    }

    /// Load OWL ontology from the OntologyStore.
    public func loadOntology() async throws -> OWLOntology? {
        if sampleRecordsProvider != nil { return nil }
        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let ontology = try await databaseSession.loadOntology()
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordSuccess(duration: duration, description: "Load ontology", operationType: .read)
            return ontology
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordFailure(duration: duration, description: "Load ontology", operationType: .read)
            databaseOperationFailureMessage = error.localizedDescription
            throw error
        }
    }

    /// Load next page when scrolling reaches the end.
    public func loadMoreItems() async {
        guard hasMoreItems, !isLoadingMoreItems, !isLoadingItems,
              let entityName = selectedEntityName else { return }

        let operationID = currentItemsLoadID
        isLoadingMoreItems = true
        databaseOperationFailureMessage = nil

        let newLimit = currentItems.count + pageSize
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let allItems = try await databaseSession.records(typeName: entityName, limit: newLimit + 1)

            // Staleness check: entity may have changed during await
            guard currentItemsLoadID == operationID, selectedEntityName == entityName else { return }

            let hasMore = allItems.count > newLimit
            let pageRecords = allItems.prefix(newLimit)
            let studioRecords = try makeStudioRecords(from: pageRecords, typeName: entityName)

            currentItemPage = StudioRecordPage(
                items: studioRecords,
                hasMore: hasMore,
                offset: 0,
                limit: newLimit
            )
            currentItems = studioRecords
            updateDiscoveredFields()

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordSuccess(duration: duration, description: "Load more items: \(entityName)", typeName: entityName, operationType: .read)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordFailure(duration: duration, description: "Load more items: \(entityName)", typeName: entityName, operationType: .read)
            databaseOperationFailureMessage = error.localizedDescription
        }

        isLoadingMoreItems = false
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
            currentCollectionStats = try await databaseSession.collectionStatistics(typeName: entityName)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordSuccess(duration: duration, description: "Load stats: \(entityName)", typeName: entityName, operationType: .read)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordFailure(duration: duration, description: "Load stats: \(entityName)", typeName: entityName, operationType: .read)
            currentCollectionStats = nil
            databaseOperationFailureMessage = error.localizedDescription
        }
    }

    // MARK: - CRUD Operations

    public func createItem(id: String, fields: [String: Any]) async throws {
        guard let entityName = selectedEntityName else {
            throw StudioError.noTypeSelected
        }

        var recordFields = fields
        recordFields["id"] = id

        guard JSONSerialization.isValidJSONObject(recordFields) else {
            throw StudioError.invalidJSON("Record fields contain a value that JSON cannot represent")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            try await databaseSession.writeRecord(typeName: entityName, fields: recordFields)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordSuccess(duration: duration, description: "Create item: \(id)", typeName: entityName, operationType: .write)
            await loadItems(for: entityName)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordFailure(duration: duration, description: "Create item: \(id)", typeName: entityName, operationType: .write)
            throw error
        }
    }

    public func updateItem(id: String, fields: [String: Any]) async throws {
        guard let entityName = selectedEntityName else {
            throw StudioError.noTypeSelected
        }

        var recordFields = fields
        recordFields["id"] = id

        guard JSONSerialization.isValidJSONObject(recordFields) else {
            throw StudioError.invalidJSON("Record fields contain a value that JSON cannot represent")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            try await databaseSession.writeRecord(typeName: entityName, fields: recordFields)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordSuccess(duration: duration, description: "Update item: \(id)", typeName: entityName, operationType: .write)
            await loadItems(for: entityName)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordFailure(duration: duration, description: "Update item: \(id)", typeName: entityName, operationType: .write)
            throw error
        }
    }

    public func deleteItem(id: String) async throws {
        guard let entityName = selectedEntityName else {
            throw StudioError.noTypeSelected
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            try await databaseSession.deleteRecord(typeName: entityName, id: id)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordSuccess(duration: duration, description: "Delete item: \(id)", typeName: entityName, operationType: .write)
            if selectedItemID == id {
                selectedItemID = nil
            }
            selectedItemIDs.remove(id)
            await loadItems(for: entityName)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordFailure(duration: duration, description: "Delete item: \(id)", typeName: entityName, operationType: .write)
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
                try await databaseSession.deleteRecord(typeName: entityName, id: id)
            }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordSuccess(duration: duration, description: "Delete \(ids.count) items", typeName: entityName, operationType: .write)
            for id in ids {
                selectedItemIDs.remove(id)
            }
            if let selectedID = selectedItemID, ids.contains(selectedID) {
                selectedItemID = nil
            }
            await loadItems(for: entityName)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordFailure(duration: duration, description: "Delete \(ids.count) items", typeName: entityName, operationType: .write)
            throw error
        }
    }

    public func importItems(records: [[String: Any]]) async throws -> Int {
        guard let entityName = selectedEntityName else {
            throw StudioError.noTypeSelected
        }

        guard JSONSerialization.isValidJSONObject(records) else {
            throw StudioError.invalidJSON("Imported records contain a value that JSON cannot represent")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            var count = 0
            for record in records {
                try await databaseSession.writeRecord(typeName: entityName, fields: record)
                count += 1
            }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordSuccess(duration: duration, description: "Import \(count) items", typeName: entityName, operationType: .write)
            await loadItems(for: entityName, offset: 0)
            return count
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            metricsRecorder.recordFailure(duration: duration, description: "Import items", typeName: entityName, operationType: .write)
            throw error
        }
    }

    // MARK: - Sample Data

    @ObservationIgnored
    private var sampleRecordsProvider: (@MainActor (String) -> [StudioRecord])?

    @ObservationIgnored
    private var sampleConnectionState: StudioDatabaseSession.ConnectionState?

    public static func sample(
        connectionState: StudioDatabaseSession.ConnectionState = .connected,
        entityTree: [EntityTreeNode] = [],
        entities: [Schema.Entity] = [],
        selectedEntityName: String? = nil,
        records: [StudioRecord] = [],
        selectedItemID: String? = nil,
        recordsProvider: (@MainActor (String) -> [StudioRecord])? = nil,
        collectionStatistics: CollectionStats? = nil
    ) -> DatabaseStudioState {
        let studioState = DatabaseStudioState()
        studioState.sampleConnectionState = connectionState
        studioState.sampleRecordsProvider = recordsProvider ?? { requestedEntityName in
            requestedEntityName == selectedEntityName ? records : []
        }
        studioState.entityTree = entityTree
        studioState.currentItems = records
        studioState.selectedItemID = selectedItemID
        studioState.currentCollectionStats = collectionStatistics
        studioState.selectedEntityName = selectedEntityName
        return studioState
    }

    private static func makeConnectionErrorPresentation(message: String) -> ConnectionErrorPresentation {
        if message.contains("Cannot connect to FDB server specified") {
            return ConnectionErrorPresentation(
                title: "Cluster Unreachable",
                message: message,
                recoverySuggestion: "Check that the selected .cluster file exists and points to a running FoundationDB server."
            )
        }

        return ConnectionErrorPresentation(
            title: "Connection Failed",
            message: message,
            recoverySuggestion: nil
        )
    }
}

// MARK: - Errors

public struct ConnectionErrorPresentation: Sendable, Equatable {
    public let title: String
    public let message: String
    public let recoverySuggestion: String?
}

public enum StudioError: Error, LocalizedError {
    case notConnected
    case noTypeSelected
    case databaseSessionUnavailable
    case invalidJSON(String)
    case recordIdentifierMissing(position: Int)
    case recordPresentationFailed(String, String)
    case databaseRuntimeRequired(StudioDatabaseOperation)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to a database"
        case .noTypeSelected: return "No type selected"
        case .databaseSessionUnavailable: return "The database session is no longer available"
        case .invalidJSON(let message): return message
        case .recordIdentifierMissing(let position):
            return "Record at position \(position) has no string id or _id field"
        case .recordPresentationFailed(let identifier, let message):
            return "Could not prepare record \(identifier) for presentation: \(message)"
        case .databaseRuntimeRequired(let operation):
            return "\(operation.displayName) requires an authenticated application database runtime; direct storage connections expose catalog inspection only."
        }
    }
}
