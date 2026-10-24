import Foundation
import Observation
import DatabaseKit
import DatabaseWire

/// Owns an applied query and its atomically published bounded result.
@Observable @MainActor
final class RuntimeQuery {
    private(set) var presentation: ResultPageState?
    private(set) var response: QueryExecuteOperation.Response?
    private(set) var selectedResultIndex = 0

    var selectedResult: QueryExecuteOperation.Response? {
        guard let response, response.results.indices.contains(selectedResultIndex) else { return nil }
        return response.results[selectedResultIndex]
    }
    private(set) var rows: [DatabaseKit.QueryRow] = []
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

    func run(_ request: QueryExecuteOperation.Request, connection: any RuntimeQueryExecuting) async {
        self.request = nil
        presentation?.cancel()
        presentation = nil
        response = nil
        rows = []
        quads = []
        pageRevision &+= 1
        await execute(request, connection: connection)
    }

    func nextPage(connection: any RuntimeQueryExecuting) async {
        guard !isRunning, let request, let requestedPage = request.page else { return }
        let page: QueryExecuteOperation.Page
        switch response {
        case .rows(let result):
            guard let continuation = result.continuation else { return }
            page = .init(limit: requestedPage.limit, continuation: continuation)
        case .rdfGraph(let result):
            guard let continuation = result.continuation else { return }
            page = .init(limit: requestedPage.limit, continuation: continuation)
        default: return
        }
        await execute(.init(input: request.input, parameters: request.parameters,
                            graphPartitions: request.graphPartitions, page: page,
                            budget: request.budget), connection: connection)
    }

    enum CollectionFailure: Error, LocalizedError {
        case capacity, invalidPage
        var errorDescription: String? {
            switch self {
            case .capacity: "The combined result exceeds the admitted row or byte budget. Narrow the source query before analysis."
            case .invalidPage: "The server returned an incompatible or non-progressing continuation page. The previous result is retained."
            }
        }
    }

    var canCollectRows: Bool {
        if case .rows = response { return hasNextPage && !isRunning }
        return false
    }

    /// Publishes the whole admitted row result once; failures retain the prior page.
    func loadRemainingPages(connection: any RuntimeQueryExecuting) async {
        guard canCollectRows, let request, let requestedPage = request.page, case .rows(let first) = response else { return }
        generation &+= 1
        let current = generation
        isRunning = true
        wasCancelled = false
        failure = nil
        do {
            let rowLimit = min(GraphNumericAnalyzer.maximumNodes, Int(request.budget.maximumRows))
            guard rows.count <= rowLimit else { throw CollectionFailure.capacity }
            var collected = rows
            var bytes = try admittedBytes(.rows(first))
            guard bytes <= request.budget.maximumIntermediateBytes else { throw CollectionFailure.capacity }
            var token = first.continuation
            var seen = Set<ByteString>()
            while let continuation = token {
                try Task.checkCancellation()
                guard generation == current else { return }
                guard seen.insert(continuation).inserted else { throw CollectionFailure.invalidPage }
                let nextRequest = QueryExecuteOperation.Request(input: request.input,
                    parameters: request.parameters, graphPartitions: request.graphPartitions,
                    page: .init(limit: requestedPage.limit, continuation: continuation), budget: request.budget)
                let result = try await connection.executeQuery(nextRequest)
                try Task.checkCancellation()
                guard generation == current else { return }
                guard case .rows(let page) = result, page.columns == first.columns,
                      page.rowCount <= Int(requestedPage.limit),
                      page.rowCount > 0 || page.continuation == nil else { throw CollectionFailure.invalidPage }
                guard page.rowCount <= rowLimit - collected.count else { throw CollectionFailure.capacity }
                let pageBytes = try admittedBytes(result)
                guard pageBytes <= request.budget.maximumIntermediateBytes - bytes else { throw CollectionFailure.capacity }
                bytes += pageBytes
                // Appending once per page preserves canonical value backing, order and duplicates.
                collected.append(contentsOf: try page.materializedRows(maximumCount: Int(requestedPage.limit)))
                token = page.continuation
                if token != nil, collected.count == rowLimit { throw CollectionFailure.capacity }
            }
            try Task.checkCancellation()
            guard generation == current else { return }
            // A collected result does not claim a common cross-page snapshot.
            let page = try QueryRowPage(columns: first.columns, rows: collected)
            let presentation = try ResultPageState(columns: first.columns, rows: collected, hasNextPage: false)
            self.presentation?.cancel()
            self.presentation = presentation
            rows = collected
            response = .rows(page)
            pageRevision &+= 1
            isRunning = false
        } catch {
            guard generation == current else { return }
            isRunning = false
            if error is CancellationError { wasCancelled = true }
            else { failure = error.localizedDescription }
        }
    }

    func selectResult(_ index: Int) {
        guard !isRunning, let response, let request,
              response.results.indices.contains(index) else { return }
        do {
            let selected = try prepareOutcome(response.results[index],
                maximumElements: Int(request.page?.limit ?? request.budget.maximumRows))
            presentation?.cancel()
            presentation = selected.presentation
            rows = selected.rows
            quads = selected.quads
            selectedResultIndex = index
            pageRevision &+= 1
        } catch { failure = String(describing: error) }
    }

    private func prepareOutcome(_ outcome: QueryExecuteOperation.Response, maximumElements: Int) throws
        -> (rows: [QueryRow], quads: [RDFQuad], presentation: ResultPageState?) {
        switch outcome {
        case .rows(let page):
            let rows = try page.materializedRows(maximumCount: maximumElements)
            return (rows, [], try ResultPageState(columns: page.columns, rows: rows, hasNextPage: page.continuation != nil))
        case .rdfGraph(let page):
            let quads = try page.materializedQuads(maximumCount: maximumElements)
            return ([], quads, ResultPageState(quads: quads, hasNextPage: page.continuation != nil))
        case .boolean, .command, .copy: return ([], [], nil)
        case .block: throw CollectionFailure.invalidPage
        }
    }

    private func admittedBytes(_ response: QueryExecuteOperation.Response) throws -> UInt64 {
        // The public wire API exposes no response size-only operation. One temporary
        // canonical frame per page bounds the cumulative payload without stringifying
        // or copying every nested field; it is released before the next request.
        UInt64(try DatabaseWireEncoder().encodeResponse(DatabaseOperationCatalog.queryExecute,
            requestID: 0, response: response).count)
    }

    func cancel() {
        generation &+= 1
        isRunning = false
        wasCancelled = true
    }

    private func execute(_ request: QueryExecuteOperation.Request, connection: any RuntimeQueryExecuting) async {
        generation &+= 1
        let current = generation
        failure = nil
        wasCancelled = false
        if let page = request.page, page.limit == 0 || page.limit > request.budget.maximumRows {
            isRunning = false
            failure = "Page size must be positive and within the execution row budget."
            return
        }
        isRunning = true
        do {
            let result = try await connection.executeQuery(request)
            try Task.checkCancellation()
            guard generation == current else { return }
            if request.page == nil {
                for outcome in result.results {
                    switch outcome {
                    case .rows(let page) where page.continuation != nil: throw CollectionFailure.invalidPage
                    case .rdfGraph(let page) where page.continuation != nil: throw CollectionFailure.invalidPage
                    default: break
                    }
                }
            }
            guard let first = result.results.first else { throw CollectionFailure.invalidPage }
            let selected = try prepareOutcome(first, maximumElements: Int(request.page?.limit ?? request.budget.maximumRows))
            self.presentation?.cancel()
            self.presentation = selected.presentation
            self.rows = selected.rows
            self.quads = selected.quads
            self.selectedResultIndex = 0
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
