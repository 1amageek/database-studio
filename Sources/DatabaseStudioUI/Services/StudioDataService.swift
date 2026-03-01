import Foundation
import DatabaseEngine
import DatabaseCLICore
import GraphIndex
import Core
import Graph
import StorageKit
import SQLiteStorage
import FDBStorage
import FoundationDB

/// Unified data service wrapping SchemaRegistry + CatalogDataAccess.
///
/// Supports both FoundationDB and SQLite backends.
/// Backend is auto-detected from the file extension.
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
    private var engine: (any StorageEngine)?

    @ObservationIgnored
    private var schemaRegistry: SchemaRegistry?

    @ObservationIgnored
    private var catalogAccess: CatalogDataAccess?

    public init() {}

    // MARK: - Connection

    /// Connect to a database by file path.
    ///
    /// Backend is auto-detected from the file extension:
    /// - `.sqlite`, `.db` → SQLite
    /// - `.cluster`, no extension → FoundationDB
    public func connect(filePath: String) async {
        disconnect()
        connectionState = .connecting
        do {
            let backendType = BackendType.detect(from: filePath)
            switch backendType {
            case .foundationDB:
                if !FDBClient.isInitialized {
                    try await FDBClient.initialize()
                }
                let db = try FDBClient.openDatabase(clusterFilePath: filePath)
                self.engine = FDBStorageEngine(database: db)
            case .sqlite:
                self.engine = try SQLiteStorageEngine(path: filePath)
            }
            guard let engine else {
                connectionState = .error("Failed to create storage engine")
                return
            }
            self.schemaRegistry = SchemaRegistry(database: engine)
            connectionState = .connected
            try await loadEntities()
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    public func disconnect() {
        engine?.shutdown()
        engine = nil
        schemaRegistry = nil
        catalogAccess = nil
        entities = []
        connectionState = .disconnected
    }

    // MARK: - Schema

    public func loadEntities() async throws {
        guard let registry = schemaRegistry else { throw StudioError.notConnected }
        let loaded = try await registry.loadAll()
        self.entities = loaded.sorted { $0.name < $1.name }
        guard let engine else { throw StudioError.notConnected }
        self.catalogAccess = CatalogDataAccess(database: engine, entities: loaded)
    }

    // MARK: - Data Access

    public func findAll(typeName: String, limit: Int? = nil, partitionValues: [String: String] = [:]) async throws -> [[String: Any]] {
        guard let access = catalogAccess else { throw StudioError.notConnected }
        return try await access.findAll(typeName: typeName, limit: limit, partitionValues: partitionValues)
    }

    public func getItem(typeName: String, id: String, partitionValues: [String: String] = [:]) async throws -> [String: Any]? {
        guard let access = catalogAccess else { throw StudioError.notConnected }
        return try await access.get(typeName: typeName, id: id, partitionValues: partitionValues)
    }

    public func insertItem(typeName: String, dict: sending [String: Any], partitionValues: [String: String] = [:]) async throws {
        guard let access = catalogAccess else { throw StudioError.notConnected }
        try await access.insert(typeName: typeName, dict: dict, partitionValues: partitionValues)
    }

    public func deleteItem(typeName: String, id: String, partitionValues: [String: String] = [:]) async throws {
        guard let access = catalogAccess else { throw StudioError.notConnected }
        try await access.delete(typeName: typeName, id: id, partitionValues: partitionValues)
    }

    // MARK: - Statistics

    public func collectionStats(typeName: String, partitionValues: [String: String] = [:]) async throws -> CollectionStats {
        guard let access = catalogAccess else { throw StudioError.notConnected }
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

    // MARK: - Ontology

    public func loadOntology() async throws -> OWLOntology? {
        guard let engine else { throw StudioError.notConnected }
        return try await Self.performLoadOntology(engine: engine)
    }

    /// Perform ontology loading outside MainActor isolation.
    ///
    /// Separated to avoid Sendable closure issues when passing closures
    /// from @MainActor context to StorageEngine.withTransaction().
    private static nonisolated func performLoadOntology(engine: any StorageEngine) async throws -> OWLOntology? {
        let store = OntologyStore.default()
        let iris = try await engine.withTransaction { tx in
            try await store.listOntologies(transaction: tx)
        }
        guard let firstIRI = iris.first else { return nil }
        return try await engine.withTransaction { tx in
            try await store.reconstruct(iri: firstIRI, transaction: tx)
        }
    }

    // MARK: - Entity Lookup

    public func entity(for typeName: String) -> Schema.Entity? {
        entities.first { $0.name == typeName }
    }
}
