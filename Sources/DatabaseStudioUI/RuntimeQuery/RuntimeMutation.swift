import Foundation
import Observation
import DatabaseWire

/// Presents mutation outcomes without treating interruption as rollback.
@Observable @MainActor
final class RuntimeMutation {
    private(set) var response: MutationExecuteOperation.Response?
    private(set) var isRunning = false
    private(set) var failure: String?
    @ObservationIgnored private var generation: UInt64 = 0

    func execute(_ request: MutationExecuteOperation.Request, connection: RuntimeConnection) async {
        generation &+= 1
        let current = generation
        response = nil
        failure = nil
        isRunning = true
        do {
            let result = try await connection.execute(DatabaseOperationCatalog.mutationExecute, request: request,
                metadata: .init(idempotencyKey: UUID().uuidString))
            try Task.checkCancellation()
            guard generation == current else { return }
            response = result
            isRunning = false
        } catch {
            guard generation == current else { return }
            isRunning = false
            failure = "\(error)\nVerify the data before retrying; an interrupted response does not prove rollback."
        }
    }

    func cancel() {
        generation &+= 1
        isRunning = false
        failure = "Request cancelled. Verify the data before retrying; cancellation does not prove rollback."
    }
}
