import Foundation
import os
import DatabaseEngine
import DatabaseCLICore
import GraphIndex
import OntologyIndex
import DatabaseKit
import StorageKit
import StorageKitSystemClock
import SQLiteStorage
import FDBStorage
import FoundationDB

private let logger = Logger(subsystem: "DatabaseStudio", category: "Connection")

/// Owns Database Studio's validated direct-storage inspection session.
///
/// Direct storage sessions expose schema and ontology inspection. Record-level
/// operations require an authenticated application database runtime.
@MainActor
@Observable
public final class StudioDatabaseSession {

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
    private let clock = SystemStorageClock()

    public init() {}

    // MARK: - Connection

    /// Connect to a database by file path.
    ///
    /// The storage kind is detected from the file extension:
    /// - `.sqlite`, `.db` → SQLite
    /// - `.cluster`, no extension → FoundationDB
    public func connect(filePath: String) async {
        disconnect()
        connectionState = .connecting
        do {
            try Task.checkCancellation()
            let storageKind = DatabaseStorageKind.detect(from: filePath)
            switch storageKind {
            case .foundationDB:
                try await connectToFoundationDB(clusterFilePath: filePath)
            case .sqlite:
                self.engine = try SQLiteStorageEngine(configuration: .file(filePath))
            }
            guard let engine else {
                connectionState = .error("Failed to create storage engine")
                return
            }
            self.schemaRegistry = SchemaRegistry(database: engine, clock: clock)
            connectionState = .connected
            try await loadEntities()
        } catch is CancellationError {
            disconnect()
        } catch {
            let errorDescription = error.localizedDescription
            disconnect()
            connectionState = .error(errorDescription)
        }
    }

    /// Connects to a running FoundationDB cluster.
    private func connectToFoundationDB(clusterFilePath: String) async throws {
        logger.info("Connecting to FDB: \(clusterFilePath)")
        try Task.checkCancellation()

        if !FDBClient.isInitialized {
            try await FDBClient.initialize()
        }

        let database = try FDBClient.openDatabase(clusterFilePath: clusterFilePath)
        let engine = try await FDBStorageEngine(configuration: .init(database: database))

        do {
            try await Self.probeConnection(engine: engine)
            logger.info("Connection succeeded")
            self.engine = engine
        } catch is CancellationError {
            engine.requestShutdown()
            throw CancellationError()
        } catch {
            engine.requestShutdown()
            throw FoundationDBConnectionError.cannotConnect(clusterFilePath)
        }
    }

    /// Lightweight probe to verify the FDB connection is alive.
    private static nonisolated func probeConnection(
        engine: FDBStorageEngine,
        timeoutMilliseconds: Int = 2000
    ) async throws {
        try await engine.withTransaction { transaction in
            try transaction.setOption(
                forOption: .timeout(milliseconds: timeoutMilliseconds)
            )
            _ = try await transaction.getReadVersion()
        }
    }

    public func disconnect() {
        engine?.requestShutdown()
        engine = nil
        schemaRegistry = nil
        entities = []
        connectionState = .disconnected
    }

    public func cancelConnectionAttempt() {
        guard case .connecting = connectionState else { return }
        disconnect()
    }

    // MARK: - Schema

    public func loadEntities() async throws {
        guard let engine, let registry = schemaRegistry else {
            throw StudioError.notConnected
        }
        _ = try await CatalogDataAccess.open(database: engine, clock: clock)
        let loaded = try await registry.loadAll()
        self.entities = loaded.sorted { $0.name < $1.name }
    }

    // MARK: - Record Access

    public func records(
        typeName: String,
        limit: Int? = nil,
        partitionValues: [String: String] = [:]
    ) async throws -> [[String: Any]] {
        return try requireDatabaseRuntime(for: .listRecords)
    }

    public func record(
        typeName: String,
        id: String,
        partitionValues: [String: String] = [:]
    ) async throws -> [String: Any]? {
        return try requireDatabaseRuntime(for: .readRecord)
    }

    public func writeRecord(
        typeName: String,
        fields: sending [String: Any],
        partitionValues: [String: String] = [:]
    ) async throws {
        return try requireDatabaseRuntime(for: .writeRecord)
    }

    public func deleteRecord(
        typeName: String,
        id: String,
        partitionValues: [String: String] = [:]
    ) async throws {
        return try requireDatabaseRuntime(for: .deleteRecord)
    }

    // MARK: - Statistics

    public func collectionStatistics(
        typeName: String,
        partitionValues: [String: String] = [:]
    ) async throws -> CollectionStats {
        return try requireDatabaseRuntime(for: .readCollectionStatistics)
    }

    // MARK: - Ontology

    public func loadOntology() async throws -> OWLOntology? {
        guard let engine else { throw StudioError.notConnected }
        return try await Self.readFirstOntology(from: engine)
    }

    /// Perform ontology loading outside MainActor isolation.
    ///
    /// Separated to avoid Sendable closure issues when passing closures
    /// from @MainActor context to StorageEngine.withTransaction().
    private static nonisolated func readFirstOntology(from engine: any StorageEngine) async throws -> OWLOntology? {
        let store = OntologyStore.default()
        let ontologyIdentifiers = try await engine.withTransaction { transaction in
            try await store.listOntologies(transaction: transaction)
        }
        guard let firstOntologyIdentifier = ontologyIdentifiers.first else { return nil }
        return try await engine.withTransaction { transaction in
            try await store.reconstruct(iri: firstOntologyIdentifier, transaction: transaction)
        }
    }

    // MARK: - Entity Lookup

    public func entity(for typeName: String) -> Schema.Entity? {
        entities.first { $0.name == typeName }
    }

    /// Direct storage currently exposes catalog inspection only. The current
    /// call path must fail until an authenticated DatabaseWire runtime is
    /// configured; record operations must never be reported as successful here.
    private func requireDatabaseRuntime<Result>(
        for operation: StudioDatabaseOperation
    ) throws -> Result {
        guard engine != nil else {
            throw StudioError.notConnected
        }
        throw StudioError.databaseRuntimeRequired(operation)
    }
}

// MARK: - FDB Connection Errors

enum FoundationDBConnectionError: Error, LocalizedError {
    case cannotConnect(String)

    var errorDescription: String? {
        switch self {
        case .cannotConnect(let path):
            return "Cannot connect to FDB server specified in \(path). Ensure the server is running."
        }
    }
}
