import XCTest
import DatabaseKit
import DatabaseWire
@testable import DatabaseStudioUI

@MainActor
final class RuntimeQueryCollectionTests: XCTestCase {
    private final class Source: RuntimeQueryExecuting {
        var requests: [QueryExecuteOperation.Request] = []
        var pages: [QueryExecuteOperation.Response] = []
        var suspended: CheckedContinuation<QueryExecuteOperation.Response, any Error>?
        var shouldSuspend = false
        func executeQuery(_ request: QueryExecuteOperation.Request) async throws -> QueryExecuteOperation.Response {
            requests.append(request)
            if shouldSuspend { return try await withCheckedThrowingContinuation { suspended = $0 } }
            return pages.removeFirst()
        }
    }

    private func page(_ values: [Int32], token: UInt8? = nil, name: String = "value") throws -> QueryExecuteOperation.Response {
        .rows(try QueryRowPage(columns: [.init(number: 1, name: name, type: .primitive(.int32), isNullable: true)],
            rows: values.map { .init(values: [.int32($0)].map(DatabaseKit.QueryValue.primitive)) }, continuation: token.map { ByteString([$0]) }))
    }

    func testCompleteOutcomesKeepOrderKindsAndIndependentSelection() async throws {
        let source = Source()
        let copied = ByteString([0, 255, 10])
        source.pages = [try .init(results: [.command(.createTable, affectedRows: nil),
            page([7, 7]), .copy(bytes: copied, affectedRows: 2), .boolean(true)])]
        let query = RuntimeQuery()
        await query.run(.init(input: .sql("complete block")), connection: source)
        XCTAssertNil(query.failure)
        XCTAssertEqual(query.response?.results.count, 4)
        XCTAssertEqual(query.selectedResult?.command, .createTable)
        XCTAssertTrue(query.rows.isEmpty)
        query.selectResult(1)
        XCTAssertEqual(query.rows.count, 2)
        XCTAssertNotNil(query.presentation)
        query.selectResult(2)
        XCTAssertTrue(query.rows.isEmpty)
        XCTAssertNil(query.presentation)
        guard case .copy(let bytes, let count) = query.selectedResult else { return XCTFail("Expected retained COPY") }
        XCTAssertEqual(bytes, copied)
        XCTAssertEqual(count, 2)
        query.selectResult(3)
        guard case .boolean(true) = query.selectedResult else { return XCTFail("Expected retained Boolean") }
        XCTAssertFalse(query.hasNextPage)
        XCTAssertFalse(query.canCollectRows)
    }

    func testCollectionPreservesAppliedRequestDuplicatesAndPresentation() async throws {
        let source = Source()
        source.pages = try [page([1, 1], token: 1), page([2, 3], token: 2), page([4])]
        let query = RuntimeQuery()
        let request = QueryExecuteOperation.Request(input: .text(language: .sql, statement: "SELECT value FROM Items"),
            graphPartitions: try FieldObject([("scope", .string("exact"))]), page: .init(limit: 2))
        await query.run(request, connection: source)
        let first = try XCTUnwrap(query.presentation)
        first.mode = .document
        XCTAssertTrue(query.presentation === first)
        let revision = query.pageRevision
        await query.loadRemainingPages(connection: source)
        XCTAssertNil(query.failure)
        XCTAssertEqual(query.rows.map(\.values), [[.int32(1)], [.int32(1)], [.int32(2)], [.int32(3)], [.int32(4)]].map { $0.map(DatabaseKit.QueryValue.primitive) })
        XCTAssertFalse(query.hasNextPage)
        XCTAssertEqual(query.pageRevision, revision + 1)
        XCTAssertEqual(query.presentation?.mode, .table)
        for followup in source.requests.dropFirst() {
            XCTAssertEqual(followup.input, request.input)
            XCTAssertEqual(followup.parameters, request.parameters)
            XCTAssertEqual(followup.graphPartitions, request.graphPartitions)
            XCTAssertEqual(followup.budget, request.budget)
        }
        XCTAssertEqual(source.requests[1].page?.continuation, ByteString([1]))
        XCTAssertEqual(source.requests[2].page?.continuation, ByteString([2]))
    }

    func testInvalidOrExcessiveCollectionRetainsPriorPageAndToken() async throws {
        let invalid = try [page([2], name: "changed"), page([], token: 2), page([2], token: 1), page([2, 3]), .boolean(true)]
        for response in invalid {
            let source = Source()
            source.pages = try [page([1], token: 1), response]
            let query = RuntimeQuery()
            await query.run(.init(input: .text(language: .sql, statement: "applied"), page: .init(limit: 1)), connection: source)
            let first = query.presentation
            let revision = query.pageRevision
            await query.loadRemainingPages(connection: source)
            XCTAssertNotNil(query.failure)
            XCTAssertEqual(query.rows.map(\.values), [[.int32(1)]].map { $0.map(DatabaseKit.QueryValue.primitive) })
            XCTAssertTrue(query.presentation === first)
            XCTAssertEqual(query.pageRevision, revision)
            XCTAssertTrue(query.hasNextPage)
        }
        for budget in [ExecutionBudget(maximumRows: 1), ExecutionBudget(maximumIntermediateBytes: 1)] {
            let source = Source()
            source.pages = try [page([1], token: 1), page([2])]
            let query = RuntimeQuery()
            await query.run(.init(input: .text(language: .sql, statement: "applied"), page: .init(limit: 1), budget: budget), connection: source)
            await query.loadRemainingPages(connection: source)
            XCTAssertNotNil(query.failure)
            XCTAssertEqual(query.rows.count, 1)
            XCTAssertTrue(query.hasNextPage)
        }
    }

    func testCancelledCollectionCannotPublishAfterSourceReplacement() async throws {
        let source = Source()
        source.pages = try [page([1], token: 1)]
        let workspace = RuntimeQueryWorkspace()
        workspace.statement = "retained draft"
        let query = workspace.query
        await query.run(.init(input: .text(language: .sql, statement: "applied"), page: .init(limit: 1)), connection: source)
        query.presentation?.selectedIDs = [0]
        let first = query.presentation
        source.shouldSuspend = true
        let task = Task { await query.loadRemainingPages(connection: source) }
        while source.suspended == nil { await Task.yield() }
        query.cancel()
        source.suspended?.resume(returning: try page([2]))
        await task.value
        XCTAssertTrue(query.wasCancelled)
        XCTAssertTrue(query.presentation === first)
        XCTAssertEqual(query.rows.count, 1)
        XCTAssertEqual(query.presentation?.selectedIDs, [0])
        XCTAssertEqual(workspace.statement, "retained draft")
        source.shouldSuspend = false
        source.pages = try [page([9])]
        await query.run(.init(input: .text(language: .sql, statement: "replacement")), connection: source)
        XCTAssertEqual(query.rows.first?.values, [.primitive(.int32(9))])
        XCTAssertFalse(query.presentation === first)
        XCTAssertFalse(query.wasCancelled)
    }
}
