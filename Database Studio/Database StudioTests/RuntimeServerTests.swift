import XCTest
import DatabaseClient
import DatabaseClientHTTP
import DatabaseWire
import DatabaseKit
@testable import DatabaseStudioUI

@MainActor
final class RuntimeServerTests: XCTestCase {
    private func configuration(tokenOverride: String? = nil) throws -> HTTPDatabaseConfiguration {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["STUDIO_RUNTIME_TEST_CREDENTIAL"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let endpoint = try XCTUnwrap(values["endpoint"] as? String)
        let token = try XCTUnwrap(values["token"] as? String)
        return try HTTPDatabaseConfiguration(endpoint: XCTUnwrap(URL(string: endpoint)),
                                             accessToken: tokenOverride ?? token, requestTimeout: 5)
    }

    func testRDFPageProjectionPreservesGraphScopeAndLiteralValues() throws {
        let subject = RDFSubject.iri(try RDFIRI("urn:subject"))
        let predicate = try RDFPredicateIRI("urn:label")
        let otherGraph = RDFGraphName(try RDFSubject.iri(RDFIRI("urn:other")))
        let first = RDFTerm.string("first")
        let second = try RDFTerm.langString("second", language: "en")
        let quads = [
            RDFQuad(subject: subject, predicate: predicate, object: first),
            RDFQuad(subject: subject, predicate: predicate, object: second),
            RDFQuad(subject: subject, predicate: try RDFPredicateIRI("urn:custom#type"), object: .iri(try RDFIRI("urn:object"))),
            RDFQuad(subject: subject, predicate: predicate, object: .iri(try RDFIRI("urn:separate")), graph: otherGraph)
        ]
        let page = RuntimeGraphPage(quads: quads)
        let document = try page.document(in: nil)
        XCTAssertEqual(document.nodes.count, 2)
        XCTAssertEqual(document.edges.count, 1)
        XCTAssertEqual(document.edges.first?.edgeKind, .relationship)
        XCTAssertEqual(document.nodes.first { $0.id == "urn:subject" }?.metadata["urn:label"], first.description + "\n" + second.description)
        let named = try page.document(in: otherGraph)
        XCTAssertEqual(named.edges.first?.targetID, "urn:separate")
        XCTAssertFalse(named.nodes.contains { $0.id == "urn:object" })
        let quoted = RDFTerm.tripleTerm(subject: subject, predicate: predicate, object: first)
        XCTAssertThrowsError(try RuntimeGraphPage(quads: [RDFQuad(subject: subject, predicate: predicate, object: quoted)]).document(in: nil))
    }

    func testRealHandshakeCatalogAndShutdown() async throws {
        let connection = RuntimeConnection()
        do {
            try await connection.connect(configuration: configuration())
            XCTAssertTrue(connection.isConnected)
            XCTAssertEqual(connection.capabilities?.runtimeVersion, "26.1026.0")
            XCTAssertNotNil(connection.schema)
            XCTAssertTrue(connection.capabilities?.features.contains { $0.identifier == "schema.execute" } == true)
            let capabilities = try await connection.execute(DatabaseOperationCatalog.capabilitiesDescribe,
                                                            request: EmptyOperationPayload())
            XCTAssertEqual(capabilities, connection.capabilities)
        } catch {
            await connection.disconnect()
            throw error
        }
        await connection.disconnect()
        XCTAssertFalse(connection.isConnected)
        do {
            _ = try await connection.execute(DatabaseOperationCatalog.capabilitiesDescribe, request: EmptyOperationPayload())
            XCTFail("Disconnected transport must not be used")
        } catch RuntimeConnectionError.notConnected {} catch { throw error }
    }

    func testRealServerRejectsInvalidCredentialWithoutPublishingCatalog() async throws {
        let connection = RuntimeConnection()
        do {
            try await connection.connect(configuration: configuration(tokenOverride: "invalid-test-token"))
            await connection.disconnect()
            XCTFail("Invalid credentials must fail")
        } catch let error as DatabaseClientError {
            guard case .transport(.rejected(let code, _)) = error else { throw error }
            XCTAssertEqual(code, "http_status_401")
        }
        XCTAssertFalse(connection.isConnected)
        XCTAssertNil(connection.schema)
        XCTAssertNil(connection.capabilities)
        XCTAssertFalse(connection.isConnecting)
        await connection.disconnect()
    }

    func testServerQueryPreservesValuesAndReportsInvalidInput() async throws {
        let connection = RuntimeConnection()
        try await connection.connect(configuration: configuration())
        let query = RuntimeQuery()
        await query.run(.init(input: .text(language: .sql, statement: "SELECT 1 AS value")), connection: connection)
        XCTAssertNil(query.failure)
        if case .rows(let page) = query.response {
            do {
                let rows = try page.materializedRows(maximumCount: 1)
                XCTAssertEqual(rows.count, 1)
                XCTAssertEqual(rows.first?.values, [.primitive(.int32(1))])
            } catch { XCTFail(String(describing: error)) }
        } else { XCTFail("Expected typed query rows") }
        await query.run(.init(input: .sql("SELECT CAST(1 AS bigint) AS value")), connection: connection)
        XCTAssertNil(query.failure)
        let textColumns = query.presentation?.columns
        let textRows = query.rows.map(\.values)
        let statement = QueryStatement.select(SelectQuery(projection: [.expression(.literal(.int(1)), alias: "value")], source: .values([[]])))
        await query.run(.init(input: .statement(statement)), connection: connection)
        XCTAssertNil(query.failure)
        XCTAssertEqual(query.presentation?.columns, textColumns)
        XCTAssertEqual(query.rows.map(\.values), textRows)
        let block = try SQLBlock(steps: [.statement(statement), .statement(statement)])
        await query.run(.init(input: .block(block)), connection: connection)
        XCTAssertNil(query.failure)
        XCTAssertEqual(query.response?.results.count, 2)
        query.selectResult(1)
        XCTAssertEqual(query.rows.map(\.values), textRows)
        await query.run(.init(input: .sql("BEGIN; SELECT 1 AS value; COPY (SELECT 1 AS value) TO STDOUT WITH (FORMAT CSV); COMMIT")), connection: connection)
        XCTAssertNil(query.failure)
        XCTAssertEqual(query.response?.results.count, 4)
        XCTAssertEqual(query.selectedResult?.command, .begin)
        query.selectResult(1)
        XCTAssertEqual(query.rows.first?.values, [.primitive(.int32(1))])
        query.selectResult(2)
        guard case .copy(let payload, 1) = query.selectedResult else { return XCTFail("Expected complete COPY outcome") }
        XCTAssertEqual(payload, ByteString(Array("1\n".utf8)))
        query.selectResult(3)
        XCTAssertEqual(query.selectedResult?.command, .commit)
        await query.run(.init(input: .text(language: .sql, statement: "invalid SQL")), connection: connection)
        XCTAssertNotNil(query.failure)
        XCTAssertNil(query.response)
        XCTAssertFalse(query.isRunning)
        await query.run(.init(input: .text(language: .sql, statement: "SELECT 1"), page: .init(limit: 0)), connection: connection)
        XCTAssertNotNil(query.failure)
        XCTAssertFalse(query.isRunning)
        await connection.disconnect()
    }

    func testInlineValuePagingSortingAndCancellation() async throws {
        let connection = RuntimeConnection()
        try await connection.connect(configuration: configuration())
        let query = RuntimeQuery()
        let statement = SelectQuery(projection: [.wildcard()],
            source: .aliased(.values([[.int(2)], [.int(3)], [.int(1)]]), name: "input", columns: ["score"]),
            orderBy: [SortKey(.column(ColumnRef("score")))])
        let request = QueryExecuteOperation.Request(input: .statement(.select(statement)), page: .init(limit: 1))
        await query.run(request, connection: connection)
        for score in 1...3 {
            XCTAssertNil(query.failure)
            XCTAssertEqual(query.rows.map(\.values), [[.primitive(.int64(Int64(score)))]])
            XCTAssertEqual(query.hasNextPage, score < 3)
            if score < 3 { await query.nextPage(connection: connection) }
        }
        let cancelled = Task { await query.run(request, connection: connection) }
        cancelled.cancel()
        await cancelled.value
        XCTAssertTrue(query.wasCancelled)
        XCTAssertNil(query.response)
        XCTAssertFalse(query.isRunning)
        await connection.disconnect()
    }

    func testTypedServerFilterBeforePaging() async throws {
        var filter = RuntimeRecordFilter(field: "score", comparison: .greaterThan, valueType: .int64, text: "1")
        let connection = RuntimeConnection()
        try await connection.connect(configuration: configuration())
        do {
            let query = RuntimeQuery()
            let statement = SelectQuery(projection: [.wildcard()],
                source: .aliased(.values([[.int(1)], [.int(3)], [.int(2)]]), name: "input", columns: ["score"]),
                filter: try filter.expression(), orderBy: [SortKey(.column(ColumnRef("score")))])
            await query.run(.init(input: .statement(.select(statement)), page: .init(limit: 1)), connection: connection)
            XCTAssertNil(query.failure)
            XCTAssertEqual(query.rows.map(\.values), [[.primitive(.int64(2))]])
            XCTAssertTrue(query.hasNextPage)
            filter.text = "100"
            await query.nextPage(connection: connection)
            XCTAssertNil(query.failure)
            XCTAssertEqual(query.rows.map(\.values), [[.primitive(.int64(3))]])
            XCTAssertFalse(query.hasNextPage)
            filter.text = "9223372036854775807"
            XCTAssertEqual(try filter.expression(), .greaterThan(.column(ColumnRef("score")), .literal(.int(Int64.max))))
            filter.text = "9223372036854775808"
            XCTAssertThrowsError(try filter.expression())
            filter.valueType = .uint64
            filter.text = "18446744073709551615"
            XCTAssertEqual(try filter.expression(), .greaterThan(.column(ColumnRef("score")), .literal(.uint(UInt64.max))))
            filter.valueType = .double
            filter.text = "nan"
            XCTAssertThrowsError(try filter.expression())
            await connection.disconnect()
        } catch {
            await connection.disconnect()
            throw error
        }
    }

    func testIdenticalPagesHaveDistinctRevisionsAndFailurePreservesPage() async throws {
        let connection = RuntimeConnection()
        try await connection.connect(configuration: configuration())
        let query = RuntimeQuery()
        let statement = SelectQuery(projection: [.wildcard()],
            source: .aliased(.values([[.int(7)], [.int(7)], [.int(7)]]), name: "input", columns: ["score"]))
        await query.run(.init(input: .statement(.select(statement)), page: .init(limit: 1)), connection: connection)
        XCTAssertNil(query.failure)
        let firstRevision = query.pageRevision
        let firstRows = query.rows
        await query.nextPage(connection: connection)
        XCTAssertNil(query.failure)
        XCTAssertEqual(query.rows, firstRows)
        XCTAssertGreaterThan(query.pageRevision, firstRevision)
        XCTAssertTrue(query.hasNextPage)
        let secondRevision = query.pageRevision
        await connection.disconnect()
        await query.nextPage(connection: connection)
        XCTAssertNotNil(query.failure)
        XCTAssertEqual(query.rows, firstRows)
        XCTAssertEqual(query.pageRevision, secondRevision)
        XCTAssertTrue(query.hasNextPage)
    }

    /// The harness server is fresh and publishes only these fixtures. Each install
    /// republishes every present fixture plus the requested one under a newer
    /// version, so tests sharing the server do not depend on execution order.
    private func installQuerySchema(connection: RuntimeConnection, entityName: String = "StudioQueryItem") async throws {
    let fixtureNames: Set<String> = ["StudioQueryItem", "StudioRefreshItem"]
    let published = try await connection.execute(DatabaseOperationCatalog.schemaDescribe, request: EmptyOperationPayload())
    let present = Set(published.entities.map(\.name))
    XCTAssertTrue(present.isSubset(of: fixtureNames), "Unexpected entities on the harness server: \(present)")
    XCTAssertTrue(fixtureNames.contains(entityName))
    guard !present.contains(entityName) else { return }
    let entities = try present.union([entityName]).sorted().map { name in
        try Schema.Entity(name: name, identifierType: .string, fields: [
            FieldSchema(name: "id", fieldNumber: 1, type: .string),
            FieldSchema(name: "score", fieldNumber: 2, type: .int64)
        ], directoryComponents: [.staticPath("studio_fixture_" + name.lowercased())])
    }
    let version = present.isEmpty ? Schema.Version(1, 0, 0)
        : Schema.Version(published.version.major, published.version.minor + 1, 0)
    let entity = try XCTUnwrap(entities.first { $0.name == entityName })
    let manifest = SchemaManifest(schema: try Schema(entities: entities, version: version))
    let planned = try await connection.execute(DatabaseOperationCatalog.schemaExecute,
        request: .init(invocation: .plan(manifest: manifest, expectedFingerprint: nil)))
    guard case .plan(let plan) = planned else { throw CocoaError(.coderReadCorrupt) }
    let current = try XCTUnwrap(plan.currentFingerprint)
    let applied = try await connection.execute(DatabaseOperationCatalog.schemaExecute,
        request: .init(invocation: .apply(manifest: manifest, expectedFingerprint: current, idempotencyKey: UUID().uuidString)))
    switch applied {
    case .applied: break
    case .accepted(let job):
        var completed = false
        for _ in 0..<50 {
            let status = try await connection.execute(DatabaseOperationCatalog.jobStatus, request: .init(job: job))
            if status.state == .succeeded { completed = true; break }
            if status.state == .failed || status.state == .cancelled {
                XCTFail("Schema job ended with \(status.state)")
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard completed else { throw CocoaError(.fileWriteUnknown) }
    case .plan: throw CocoaError(.coderReadCorrupt)
    }
    let catalog = try await connection.execute(DatabaseOperationCatalog.schemaDescribe, request: EmptyOperationPayload())
    XCTAssertTrue(catalog.entities.contains { $0.name == entity.name })
    }

    func testSchemaRefreshPublishesAppliedSchemaAndRejectsDisconnectedRefresh() async throws {
        let connection = RuntimeConnection()
        try await connection.connect(configuration: configuration())
        do {
            XCTAssertFalse(connection.schema?.entities.contains { $0.name == "StudioRefreshItem" } == true)
            try await installQuerySchema(connection: connection, entityName: "StudioRefreshItem")
            XCTAssertFalse(connection.schema?.entities.contains { $0.name == "StudioRefreshItem" } == true)
            try await connection.refreshSchema()
            XCTAssertTrue(connection.schema?.entities.contains { $0.name == "StudioRefreshItem" } == true)
            await connection.disconnect()
            do {
                try await connection.refreshSchema()
                XCTFail("Disconnected refresh must fail")
            } catch {
                XCTAssertNil(connection.schema)
            }
        } catch {
            await connection.disconnect()
            throw error
        }
    }

    func testPersistedCRUDAndContinuation() async throws {
        let connection = RuntimeConnection()
        try await connection.connect(configuration: configuration())
        do {
            try await installQuerySchema(connection: connection)
            let mutation = RuntimeMutation()
            for score in 1...3 {
                await mutation.execute(.init(input: .statement(.text(language: .sql,
                    statement: "INSERT INTO \"StudioQueryItem\" (id, score) VALUES ('item-\(score)', \(score))"), parameters: [])), connection: connection)
                XCTAssertNil(mutation.failure)
                XCTAssertNotNil(mutation.response)
            }
            let query = RuntimeQuery()
            await query.run(.init(input: .text(language: .sql,
                statement: "SELECT score FROM \"StudioQueryItem\" ORDER BY score"), page: .init(limit: 1)), connection: connection)
            for score in 1...3 {
                XCTAssertNil(query.failure)
                XCTAssertEqual(query.rows.map(\.values), [[.primitive(.int64(Int64(score)))]])
                XCTAssertEqual(query.hasNextPage, score < 3)
                if score < 3 { await query.nextPage(connection: connection) }
            }
            await mutation.execute(.init(input: .statement(.text(language: .sql,
                statement: "UPDATE \"StudioQueryItem\" SET score = 9 WHERE id = 'item-1'"), parameters: [])), connection: connection)
            XCTAssertNil(mutation.failure)
            await query.run(.init(input: .text(language: .sql,
                statement: "SELECT score FROM \"StudioQueryItem\" WHERE id = 'item-1'")), connection: connection)
            XCTAssertEqual(query.rows.map(\.values), [[.primitive(.int64(9))]])
            await mutation.execute(.init(input: .statement(.text(language: .sql,
                statement: "DELETE FROM \"StudioQueryItem\" WHERE id = 'item-1'"), parameters: [])), connection: connection)
            XCTAssertNil(mutation.failure)
            await query.run(.init(input: .text(language: .sql,
                statement: "SELECT score FROM \"StudioQueryItem\" WHERE id = 'item-1'")), connection: connection)
            XCTAssertNil(query.failure)
            XCTAssertTrue(query.rows.isEmpty)
        } catch {
            await connection.disconnect()
            throw error
        }
        await connection.disconnect()
    }

    func testCancelledSchemaRefreshPreservesCatalogAndDisconnectClearsIt() async throws {
        let connection = RuntimeConnection()
        try await connection.connect(configuration: configuration())
        let catalog = try XCTUnwrap(connection.schema)
        let cancelled = Task { try await connection.refreshSchema() }
        cancelled.cancel()
        do {
            try await cancelled.value
            XCTFail("Cancelled refresh must not succeed")
        } catch is CancellationError {
            XCTAssertEqual(connection.schema, catalog)
        }
        let pending = Task { try await connection.refreshSchema() }
        await Task.yield()
        pending.cancel()
        await connection.disconnect()
        do {
            try await pending.value
            // Completion before disconnect is allowed; publication after it is not.
        } catch is CancellationError {
        } catch RuntimeConnectionError.notConnected {
        }
        XCTAssertNil(connection.schema)
        XCTAssertFalse(connection.isConnected)
    }

    func testDisconnectDuringHandshakeDoesNotRepublish() async throws {
        let connection = RuntimeConnection()
        let configuration = try configuration()
        let task = Task { try await connection.connect(configuration: configuration) }
        await Task.yield()
        task.cancel()
        await connection.disconnect()
        do { try await task.value }
        catch is CancellationError {}
        catch let error as DatabaseClientError {
            guard case .transport(.cancelled) = error else { throw error }
        }
        XCTAssertFalse(connection.isConnected)
        XCTAssertNil(connection.schema)
        XCTAssertFalse(connection.isConnecting)
    }
}
