import Foundation
import Observation
import DatabaseKit
import DatabaseWire

/// Owns one bounded page from an authenticated server query.
@Observable @MainActor
final class RuntimeQuery {
    private(set) var response: QueryExecuteOperation.Response?
    private(set) var rows: [DatabaseWire.QueryRow] = []
    private(set) var quads: [RDFQuad] = []
    private(set) var isRunning = false
    private(set) var failure: String?
    private(set) var wasCancelled = false
    private(set) var pageRevision: UInt64 = 0
    @ObservationIgnored private var request: QueryExecuteOperation.Request?
    @ObservationIgnored private var generation: UInt64 = 0

    var hasNextPage: Bool {
        switch response {
        case .rows(let page): page.continuation != nil
        case .rdfGraph(let page): page.continuation != nil
        default: false
        }
    }

    func run(_ request: QueryExecuteOperation.Request, connection: RuntimeConnection) async {
        self.request = nil
        response = nil
        rows = []
        quads = []
        pageRevision &+= 1
        await execute(request, connection: connection)
    }

    func nextPage(connection: RuntimeConnection) async {
        guard !isRunning, let request else { return }
        let page: QueryExecuteOperation.Page
        switch response {
        case .rows(let result):
            guard let continuation = result.continuation else { return }
            page = .init(limit: request.page.limit, continuation: continuation)
        case .rdfGraph(let result):
            guard let continuation = result.continuation else { return }
            page = .init(limit: request.page.limit, continuation: continuation)
        default: return
        }
        await execute(.init(input: request.input, parameters: request.parameters,
                            graphPartitions: request.graphPartitions, page: page,
                            budget: request.budget), connection: connection)
    }

    func cancel() {
        generation &+= 1
        isRunning = false
        wasCancelled = true
    }

    private func execute(_ request: QueryExecuteOperation.Request, connection: RuntimeConnection) async {
        generation &+= 1
        let current = generation
        failure = nil
        wasCancelled = false
        guard request.page.limit > 0, request.page.limit <= request.budget.maximumRows else {
            isRunning = false
            failure = "Page size must be positive and within the execution row budget."
            return
        }
        isRunning = true
        do {
            let result = try await connection.execute(DatabaseOperationCatalog.queryExecute, request: request)
            try Task.checkCancellation()
            guard generation == current else { return }
            // Materialize once at the UI ownership boundary, retaining canonical typed values.
            // Cells may redraw repeatedly without decoding the response frame each time.
            let rows: [DatabaseWire.QueryRow]
            let quads: [RDFQuad]
            switch result {
            case .rows(let page):
                rows = try page.materializedRows(maximumCount: Int(request.page.limit))
                quads = []
            case .rdfGraph(let page):
                rows = []
                quads = try page.materializedQuads(maximumCount: Int(request.page.limit))
            case .boolean:
                rows = []
                quads = []
            }
            self.rows = rows
            self.quads = quads
            self.request = request
            response = result
            pageRevision &+= 1
            isRunning = false
        } catch {
            guard generation == current else { return }
            isRunning = false
            if error is CancellationError {
                wasCancelled = true
            } else {
                failure = String(describing: error)
            }
        }
    }
}
