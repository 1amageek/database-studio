import Foundation
import os
import DatabaseEngine
import GraphIndex
import OntologyIndex
import DatabaseKit
import StorageKit
import StorageKitSystemClock
import SQLiteStorage
import FDBStorage
import FoundationDB

private let logger = Logger(subsystem: "DatabaseStudio", category: "Connection")

/// A connection's inspection and shutdown capabilities.
///
/// The session owns this value after the factory returns it. The closures keep
/// backend details below the session lifecycle state machine and make the
/// shutdown contract independently testable.
struct StudioConnectionResource: Sendable {
    let loadEntities: @Sendable () async throws -> [Schema.Entity]
    let loadOntology: @Sendable () async throws -> OWLOntology?
    let requestShutdown: @Sendable () -> Void
    let waitUntilShutdown: @Sendable () async -> Void

    init(
        loadEntities: @escaping @Sendable () async throws -> [Schema.Entity],
        loadOntology: @escaping @Sendable () async throws -> OWLOntology?,
        requestShutdown: @escaping @Sendable () -> Void,
        waitUntilShutdown: @escaping @Sendable () async -> Void
    ) {
        self.loadEntities = loadEntities
        self.loadOntology = loadOntology
        self.requestShutdown = requestShutdown
        self.waitUntilShutdown = waitUntilShutdown
    }

    func shutdown() async {
        requestShutdown()
        await waitUntilShutdown()
    }
}

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
        case disconnecting
        case connecting
        case connected
        case error(String)
    }

    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var entities: [Schema.Entity] = []

    @ObservationIgnored
    private var connectionResource: StudioConnectionResource?

    @ObservationIgnored
    private var pendingConnectionResource: StudioConnectionResource?

    @ObservationIgnored
    private var shutdownTask: Task<Void, Never>?

    @ObservationIgnored
    private var activeConnectionAttempt: ConnectionAttempt?

    @ObservationIgnored
    private var nextGeneration: UInt64 = 0

    @ObservationIgnored
    private var currentGeneration: UInt64 = 0

    @ObservationIgnored
    private let connectionFactory: @Sendable (
        _ filePath: String,
        _ storageKind: DatabaseStorageKind
    ) async throws -> StudioConnectionResource

    private struct ConnectionAttempt {
        let generation: UInt64
        let task: Task<Void, Never>
    }

    public init() {
        self.connectionFactory = Self.makeProductionConnection
    }

    init(
        connectionFactory: @escaping @Sendable (
            _ filePath: String,
            _ storageKind: DatabaseStorageKind
        ) async throws -> StudioConnectionResource
    ) {
        self.connectionFactory = connectionFactory
    }

    // MARK: - Connection

    /// Connect to a database by file path.
    ///
    /// The storage kind is detected from the file extension:
    /// - `.sqlite`, `.db` → SQLite
    /// - `.cluster`, no extension → FoundationDB
    public func connect(filePath: String) async {
        let generation = startGeneration()
        let previousAttempt = activeConnectionAttempt
        previousAttempt?.task.cancel()

        connectionState = .disconnecting
        let shutdown = detachAndStartShutdown()
        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runConnection(
                filePath: filePath,
                generation: generation,
                previousAttempt: previousAttempt?.task,
                shutdown: shutdown
            )
        }
        activeConnectionAttempt = ConnectionAttempt(
            generation: generation,
            task: operation
        )

        await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }

        if Task.isCancelled {
            operation.cancel()
            await operation.value
            if currentGeneration == generation {
                await disconnect()
            }
        }

        if activeConnectionAttempt?.generation == generation {
            activeConnectionAttempt = nil
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

    private func startGeneration() -> UInt64 {
        nextGeneration += 1
        currentGeneration = nextGeneration
        return nextGeneration
    }

    private func detachAndStartShutdown() -> Task<Void, Never>? {
        var resources: [StudioConnectionResource] = []
        if let connectionResource {
            resources.append(connectionResource)
        }
        if let pendingConnectionResource {
            resources.append(pendingConnectionResource)
        }

        connectionResource = nil
        pendingConnectionResource = nil
        entities = []

        guard !resources.isEmpty else {
            return shutdownTask
        }

        let previousShutdown = shutdownTask
        let task = Task { @MainActor in
            await previousShutdown?.value
            for resource in resources {
                await resource.shutdown()
            }
        }
        shutdownTask = task
        return task
    }

    private func runConnection(
        filePath: String,
        generation: UInt64,
        previousAttempt: Task<Void, Never>?,
        shutdown: Task<Void, Never>?
    ) async {
        await previousAttempt?.value
        await shutdown?.value
        clearCompletedShutdown(for: generation)

        guard isCurrent(generation), !Task.isCancelled else { return }
        connectionState = .connecting

        var candidate: StudioConnectionResource?
        do {
            let resource = try await connectionFactory(
                filePath,
                DatabaseStorageKind.detect(from: filePath)
            )
            candidate = resource
            pendingConnectionResource = resource

            try Task.checkCancellation()
            guard isCurrent(generation) else {
                pendingConnectionResource = nil
                await resource.shutdown()
                return
            }

            let loadedEntities = try await resource.loadEntities()
            try Task.checkCancellation()
            guard isCurrent(generation) else {
                pendingConnectionResource = nil
                await resource.shutdown()
                return
            }

            pendingConnectionResource = nil
            connectionResource = resource
            entities = loadedEntities.sorted { $0.name < $1.name }
            connectionState = .connected
        } catch is CancellationError {
            if isCurrent(generation) {
                connectionState = .disconnecting
            }
            if let candidate, pendingConnectionResource != nil {
                pendingConnectionResource = nil
                await candidate.shutdown()
            }
            await finishCancelledConnection(
                generation: generation
            )
        } catch {
            if isCurrent(generation) {
                connectionState = .disconnecting
            }
            if let candidate, pendingConnectionResource != nil {
                pendingConnectionResource = nil
                await candidate.shutdown()
            }
            await finishFailedConnection(
                generation: generation,
                error: error
            )
        }
    }

    private func finishCancelledConnection(generation: UInt64) async {
        guard isCurrent(generation) else { return }
        connectionState = .disconnecting
        let shutdown = detachAndStartShutdown()
        await shutdown?.value
        clearCompletedShutdown(for: generation)
        guard isCurrent(generation) else { return }
        connectionState = .disconnected
    }

    private func finishFailedConnection(
        generation: UInt64,
        error: any Error
    ) async {
        guard isCurrent(generation) else { return }
        connectionState = .disconnecting
        let shutdown = detachAndStartShutdown()
        await shutdown?.value
        clearCompletedShutdown(for: generation)
        guard isCurrent(generation) else { return }
        connectionState = .error(error.localizedDescription)
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        currentGeneration == generation
    }

    private static func makeProductionConnection(
        filePath: String,
        storageKind: DatabaseStorageKind
    ) async throws -> StudioConnectionResource {
        try Task.checkCancellation()

        switch storageKind {
        case .sqlite:
            let engine = try SQLiteStorageEngine(
                configuration: .file(filePath)
            )
            return makeResource(engine: engine)

        case .foundationDB:
            logger.info("Connecting to FDB: \(filePath)")
            if !FDBClient.isInitialized {
                try await FDBClient.initialize()
            }
            try Task.checkCancellation()

            let database = try FDBClient.openDatabase(
                clusterFilePath: filePath
            )
            let engine = try await FDBStorageEngine(
                configuration: .init(database: database)
            )

            do {
                try Task.checkCancellation()
                try await probeConnection(engine: engine)
                logger.info("Connection succeeded")
                return makeResource(engine: engine)
            } catch is CancellationError {
                await shutdown(engine)
                throw CancellationError()
            } catch {
                await shutdown(engine)
                throw FoundationDBConnectionError.cannotConnect(filePath)
            }
        }
    }

    private static func makeResource(
        engine: any StorageEngine
    ) -> StudioConnectionResource {
        let clock = SystemStorageClock()
        let registry = SchemaRegistry(database: engine, clock: clock)
        return StudioConnectionResource(
            loadEntities: {
                _ = try await DatabaseFormatCatalog(
                    database: engine,
                    clock: clock
                ).loadRequired()
                return try await registry.loadAll()
            },
            loadOntology: {
                try await readFirstOntology(from: engine)
            },
            requestShutdown: {
                engine.requestShutdown()
            },
            waitUntilShutdown: {
                await engine.waitUntilShutdown()
            }
        )
    }

    private static func shutdown(_ engine: any StorageEngine) async {
        engine.requestShutdown()
        await engine.waitUntilShutdown()
    }

    public func disconnect() async {
        let generation = startGeneration()
        let activeAttempt = activeConnectionAttempt
        activeAttempt?.task.cancel()
        connectionState = .disconnecting
        let shutdown = detachAndStartShutdown()

        await activeAttempt?.task.value
        await shutdown?.value
        clearCompletedShutdown(for: generation)

        guard currentGeneration == generation else { return }
        connectionState = .disconnected
    }

    public func cancelConnectionAttempt() async {
        guard activeConnectionAttempt != nil
            || connectionState == .connecting
            || connectionState == .disconnecting else {
            return
        }
        await disconnect()
    }

    private func clearCompletedShutdown(for generation: UInt64) {
        guard currentGeneration == generation else { return }
        shutdownTask = nil
    }

    // MARK: - Schema

    public func loadEntities() async throws {
        guard let resource = connectionResource else {
            throw StudioError.notConnected
        }
        let generation = currentGeneration
        let loaded = try await resource.loadEntities()
        guard isCurrent(generation), connectionResource != nil else {
            throw StudioError.notConnected
        }
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
        guard let resource = connectionResource else {
            throw StudioError.notConnected
        }
        let generation = currentGeneration
        let ontology = try await resource.loadOntology()
        guard isCurrent(generation), connectionResource != nil else {
            throw StudioError.notConnected
        }
        return ontology
    }

    /// Perform ontology loading outside MainActor isolation.
    ///
    /// Separated to avoid Sendable closure issues when passing closures
    /// from @MainActor context to StorageEngine.withTransaction().
    // FIXME(INCOMPLETE_IMPLEMENTATION): Direct-storage ontology loading currently
    // serves only the first catalog entry through loadOntology(). Multi-ontology
    // inspection is complete only when selection and all requested sources are preserved.
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
    // FIXME(INCOMPLETE_IMPLEMENTATION): Existing record and statistics callers
    // cannot use this inspection session. Completion requires routing them through
    // the authenticated runtime and verifying successful and failed operations.
    private func requireDatabaseRuntime<Result>(
        for operation: StudioDatabaseOperation
    ) throws -> Result {
        guard connectionResource != nil else {
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
