import Foundation
import DatabaseEngine
import DatabaseCLICore
import Core
import FoundationDB

/// SchemaRegistry + CatalogDataAccess をラップする統合データサービス
@MainActor
@Observable
public final class StudioDataService {
    // MARK: - Connection State

    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var entities: [Schema.Entity] = []

    @ObservationIgnored
    nonisolated(unsafe) private var database: (any DatabaseProtocol)?

    @ObservationIgnored
    private var schemaRegistry: SchemaRegistry?

    @ObservationIgnored
    private var catalogAccess: CatalogDataAccess?

    public init() {}

    // MARK: - Connection

    public func connect(clusterFilePath: String) async {
        connectionState = .connecting
        do {
            if !FDBClient.isInitialized {
                try await FDBClient.initialize()
            }
            let db = try FDBClient.openDatabase(clusterFilePath: clusterFilePath)
            self.database = db
            self.schemaRegistry = SchemaRegistry(database: db)
            connectionState = .connected
            try await loadEntities()
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    public func disconnect() {
        database = nil
        schemaRegistry = nil
        catalogAccess = nil
        entities = []
        connectionState = .disconnected
    }

    // MARK: - Schema

    public func loadEntities() async throws {
        guard let registry = schemaRegistry else { return }
        let loaded = try await registry.loadAll()
        self.entities = loaded.sorted { $0.name < $1.name }
        guard let db = database else { return }
        self.catalogAccess = CatalogDataAccess(database: db, entities: loaded)
    }

    // MARK: - Data Access

    public func findAll(typeName: String, limit: Int? = nil, partitionValues: [String: String] = [:]) async throws -> [[String: Any]] {
        guard let access = catalogAccess else { return [] }
        return try await access.findAll(typeName: typeName, limit: limit, partitionValues: partitionValues)
    }

    public func getItem(typeName: String, id: String, partitionValues: [String: String] = [:]) async throws -> [String: Any]? {
        guard let access = catalogAccess else { return nil }
        return try await access.get(typeName: typeName, id: id, partitionValues: partitionValues)
    }

    public func insertItem(typeName: String, dict: sending [String: Any], partitionValues: [String: String] = [:]) async throws {
        guard let access = catalogAccess else { return }
        try await access.insert(typeName: typeName, dict: dict, partitionValues: partitionValues)
    }

    public func deleteItem(typeName: String, id: String, partitionValues: [String: String] = [:]) async throws {
        guard let access = catalogAccess else { return }
        try await access.delete(typeName: typeName, id: id, partitionValues: partitionValues)
    }

    // MARK: - Statistics

    public func collectionStats(typeName: String, partitionValues: [String: String] = [:]) async throws -> CollectionStats {
        guard let access = catalogAccess else {
            return CollectionStats(typeName: typeName, documentCount: 0, storageSize: 0)
        }
        let items = try await access.findAll(typeName: typeName, limit: nil, partitionValues: partitionValues)
        var totalSize = 0
        for item in items {
            let data = try JSONSerialization.data(withJSONObject: item, options: [])
            totalSize += data.count
        }
        return CollectionStats(
            typeName: typeName,
            documentCount: items.count,
            storageSize: totalSize
        )
    }

    // MARK: - Entity Lookup

    public func entity(for typeName: String) -> Schema.Entity? {
        entities.first { $0.name == typeName }
    }
}
