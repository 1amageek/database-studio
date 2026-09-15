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
    var isConnected: Bool { capabilities != nil && schema != nil }

    @ObservationIgnored private var generation: UInt64 = 0
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
        isConnecting = true
        await previous?.shutdown()
        do {
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            let capabilities = try await candidateClient.database.execute(
                DatabaseOperationCatalog.capabilitiesDescribe, request: EmptyOperationPayload())
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            let schema = try await candidateClient.database.execute(
                DatabaseOperationCatalog.schemaDescribe, request: EmptyOperationPayload())
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            self.client = candidateClient
            self.capabilities = capabilities
            self.schema = schema
            isConnecting = false
        } catch {
            await candidate.shutdown()
            if generation == current {
                transport = nil
                client = nil
                capabilities = nil
                schema = nil
                isConnecting = false
            }
            if Task.isCancelled || generation != current { throw CancellationError() }
            throw error
        }
    }

    func execute<Request: Sendable, Response: Sendable>(
        _ operation: DatabaseOperation<Request, Response>, request: Request
    ) async throws -> Response {
        guard let client, isConnected else { throw RuntimeConnectionError.notConnected }
        let current = generation
        do {
            let response = try await client.database.execute(operation, request: request)
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            return response
        } catch {
            if Task.isCancelled || generation != current { throw CancellationError() }
            throw error
        }
    }

    func disconnect() async {
        generation &+= 1
        let previous = transport
        transport = nil
        client = nil
        capabilities = nil
        schema = nil
        isConnecting = false
        await previous?.shutdown()
    }
}
