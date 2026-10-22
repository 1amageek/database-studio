import DatabaseClient
import DatabaseClientHTTP
import DatabaseKit
import DatabaseWire
import XCTest
@testable import DatabaseStudioUI

@MainActor
final class StudioReleaseCompatibilityTests: XCTestCase {
    private func connect() async throws -> RuntimeConnection {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["STUDIO_RUNTIME_TEST_CREDENTIAL"])
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let endpoint = try XCTUnwrap(URL(string: XCTUnwrap(values["endpoint"] as? String)))
        let token = try XCTUnwrap(values["token"] as? String)
        let connection = RuntimeConnection()
        try await connection.connect(configuration: HTTPDatabaseConfiguration(endpoint: endpoint, accessToken: token))
        return connection
    }

    func testReleasedQueriesPreserveAggregateInputAndTypedPages() async throws {
        let connection = try await connect()
        defer { await connection.disconnect() }
        let query = RuntimeQuery()
        await query.run(.init(input: .text(language: .sql,
            statement: "SELECT count(*) FROM (VALUES(1),(2),(3)) v(score) LIMIT 1")), connection: connection)
        XCTAssertNil(query.failure)
        XCTAssertEqual(query.rows.map(\.values), [[.int64(3)]].map { $0.map(DatabaseKit.QueryValue.primitive) })

        await query.run(.init(input: .text(language: .sql,
            statement: "WITH c(score) AS (VALUES(3),(1),(2)) SELECT score FROM c ORDER BY score"),
            page: .init(limit: 1), budget: ExecutionBudget(maximumRows: 3)), connection: connection)
        for score in 1...3 {
            XCTAssertNil(query.failure)
            XCTAssertEqual(query.rows.map(\.values), [[.int32(Int32(score))]].map { $0.map(DatabaseKit.QueryValue.primitive) })
            XCTAssertEqual(query.hasNextPage, score < 3)
            if score < 3 { await query.nextPage(connection: connection) }
        }
        let cancelled = Task {
            await query.run(.init(input: .text(language: .sql, statement: "SELECT 1")), connection: connection)
        }
        cancelled.cancel()
        await cancelled.value
        XCTAssertTrue(query.wasCancelled)
        XCTAssertNil(query.response)
    }

    func testReleasedFailuresRetainBudgetsAuthorizationAndRollback() async throws {
        let connection = try await connect()
        defer { await connection.disconnect() }
        try await expectFailure("CREATE TABLE studio_release_rollback (id integer); SELECT missing_column",
            state: "42703", connection: connection)
        try await expectFailure("SELECT id FROM studio_release_rollback", state: "42P01", connection: connection)

        try await expectFailure("SELECT 1", budget: ExecutionBudget(maximumIntermediateBytes: 64),
            state: "54000", connection: connection)
        _ = try await connection.execute(DatabaseOperationCatalog.sqlExecute,
            request: .init(input: .text("CREATE TABLE studio_release_denied (id integer)")))
        try await expectFailure("WITH c AS (SELECT id FROM studio_release_denied) SELECT id FROM c",
            state: "42501", connection: connection)
        _ = try await connection.execute(DatabaseOperationCatalog.sqlExecute,
            request: .init(input: .text("DROP TABLE studio_release_denied")))

        let query = RuntimeQuery()
        await query.run(.init(input: .text(language: .sql, statement: "SELECT 7")), connection: connection)
        XCTAssertNil(query.failure)
        XCTAssertEqual(query.rows.map(\.values), [[.int32(7)]].map { $0.map(DatabaseKit.QueryValue.primitive) })
    }

    private func expectFailure(_ statement: String, budget: ExecutionBudget = ExecutionBudget(),
        state: String, connection: RuntimeConnection) async throws {
        do {
            _ = try await connection.execute(DatabaseOperationCatalog.sqlExecute,
                request: .init(input: .text(statement), budget: budget))
            XCTFail("Expected an explicit SQL failure")
        } catch let error as DatabaseClientError {
            guard case .call(.remote(let remote)) = error else { throw error }
            XCTAssertEqual(try remote.sqlDiagnostic()?.sqlState, state)
        }
    }
}
