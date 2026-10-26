import Foundation
import Observation
import DatabaseClient
import DatabaseClientHTTP
import DatabaseWire

/// Owns the authenticated runtime selected by a Studio window.
@Observable @MainActor
final class RuntimeConnection {
    private(set) var isConnecting = false
    private(set) var capabilities: CapabilitiesDescribeOperation.Response?
    private(set) var schema: SchemaDescribeOperation.Response?
    /// SQL relations for Data browsing; storage entities in `schema` are inspection only.
    private(set) var relations: [RuntimeRelation] = []
    /// A catalog failure leaves the handshake, schema inspection and Query usable.
    private(set) var relationCatalogFailure: String?
    var isConnected: Bool { capabilities != nil && schema != nil }

    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var schemaRefreshGeneration: UInt64 = 0
    @ObservationIgnored private var transport: HTTPDatabaseTransport?
    @ObservationIgnored private var client: DatabaseClient<HTTPDatabaseTransport>?

    func connect(configuration: HTTPDatabaseConfiguration) async throws {
        generation &+= 1
        let current = generation
        let previous = transport
        let candidate = HTTPDatabaseTransport(configuration: configuration)
        let candidateClient = DatabaseClient(transport: candidate)
        transport = candidate
        client = nil
        capabilities = nil
        schema = nil
        relations = []
        relationCatalogFailure = nil
        isConnecting = true
        await previous?.shutdown()
        do {
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            let capabilities = try await candidateClient.execute(
                DatabaseOperationCatalog.capabilitiesDescribe, request: EmptyOperationPayload())
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            let schema = try await candidateClient.execute(
                DatabaseOperationCatalog.schemaDescribe, request: EmptyOperationPayload())
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            let catalog = await Self.loadRelationCatalog {
                try await candidateClient.execute(DatabaseOperationCatalog.queryExecute, request: $0)
            }
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            self.client = candidateClient
            self.capabilities = capabilities
            self.schema = schema
            publish(catalog)
            isConnecting = false
        } catch {
            await candidate.shutdown()
            if generation == current {
                transport = nil
                client = nil
                capabilities = nil
                schema = nil
                relations = []
                relationCatalogFailure = nil
                isConnecting = false
            }
            if Task.isCancelled || generation != current { throw CancellationError() }
            throw error
        }
    }

    func execute<Request: Sendable, Response: Sendable>(
        _ operation: DatabaseOperation<Request, Response>, request: Request,
        metadata: OperationRequestMetadata = OperationRequestMetadata()
    ) async throws -> Response {
        guard let client, isConnected else { throw RuntimeConnectionError.notConnected }
        let current = generation
        do {
            let response = try await client.execute(operation, request: request, metadata: metadata)
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            return response
        } catch {
            if Task.isCancelled || generation != current { throw CancellationError() }
            throw error
        }
    }

    func refreshSchema() async throws {
        schemaRefreshGeneration &+= 1
        let refresh = schemaRefreshGeneration
        let current = generation
        let result = try await execute(DatabaseOperationCatalog.schemaDescribe, request: EmptyOperationPayload())
        try Task.checkCancellation()
        guard current == generation, refresh == schemaRefreshGeneration else { throw CancellationError() }
        let catalog = await Self.loadRelationCatalog {
            try await self.execute(DatabaseOperationCatalog.queryExecute, request: $0)
        }
        try Task.checkCancellation()
        guard current == generation, refresh == schemaRefreshGeneration else { throw CancellationError() }
        schema = result
        publish(catalog)
    }

    /// Callers re-check cancellation and generation; other failures become a published value.
    private static func loadRelationCatalog(
        _ execute: (QueryExecuteOperation.Request) async throws -> QueryExecuteOperation.Response
    ) async -> Result<[RuntimeRelation], any Error> {
        do { return .success(try await RuntimeRelationCatalog.load(execute)) }
        catch { return .failure(error) }
    }

    /// A failed refresh retains the previous relations and reports the failure.
    private func publish(_ catalog: Result<[RuntimeRelation], any Error>) {
        switch catalog {
        case .success(let loaded):
            relations = loaded
            relationCatalogFailure = nil
        case .failure(let error):
            relationCatalogFailure = error.localizedDescription
        }
    }

    func disconnect() async {
        generation &+= 1
        let previous = transport
        transport = nil
        client = nil
        capabilities = nil
        schema = nil
        relations = []
        relationCatalogFailure = nil
        isConnecting = false
        await previous?.shutdown()
    }
}
