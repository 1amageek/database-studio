import XCTest
import DatabaseKit
import DatabaseWire
@testable import DatabaseStudioUI

@MainActor
final class RuntimeRelationCatalogTests: XCTestCase {
    private func page(_ names: [String], _ rows: [[String]]) throws -> QueryExecuteOperation.Response {
        let columns = try names.enumerated().map {
            try QueryColumn(number: UInt32($0.offset + 1), name: $0.element, type: .primitive(.string), isNullable: true)
        }
        return .rows(try QueryRowPage(columns: columns,
            rows: rows.map { .init(values: $0.map { .primitive(.string($0)) }) }))
    }

    func testCatalogNamesRelationsAndOrderedColumnsBySQLName() async throws {
        var requests: [QueryExecuteOperation.Request] = []
        var responses = [
            try page(["table_type", "table_schema", "table_name"],
                     [["BASE TABLE", "public", "Orders"], ["BASE TABLE", "sales", "line items"]]),
            try page(["table_schema", "table_name", "column_name", "data_type", "is_nullable"],
                     [["public", "Orders", "id", "text", "NO"], ["sales", "line items", "qty", "bigint", "YES"],
                      ["sales", "line items", "sku", "text", "NO"]])
        ]
        let relations = try await RuntimeRelationCatalog.load {
            requests.append($0)
            return responses.removeFirst()
        }
        XCTAssertEqual(requests.map(\.input), [.sql(RuntimeRelationCatalog.tablesStatement), .sql(RuntimeRelationCatalog.columnsStatement)])
        XCTAssertTrue(requests.allSatisfy { $0.page == nil })
        XCTAssertEqual(relations.map(\.id), [.init(schema: "public", name: "Orders"), .init(schema: "sales", name: "line items")])
        XCTAssertEqual(relations[1].columns, [.init(name: "qty", dataType: "bigint", isNullable: true),
                                              .init(name: "sku", dataType: "text", isNullable: false)])
        XCTAssertEqual(relations[1].tableReference, TableRef(schema: "sales", table: "line items"))
    }

    func testMalformedCatalogFailsInsteadOfShowingPartialRelations() async throws {
        let tables = try page(["table_schema", "table_name", "table_type"], [["public", "a", "BASE TABLE"]])
        let orphan = try page(["table_schema", "table_name", "column_name", "data_type", "is_nullable"],
                              [["public", "missing", "x", "text", "YES"]])
        var responses = [tables, orphan]
        do {
            _ = try await RuntimeRelationCatalog.load { _ in responses.removeFirst() }
            XCTFail("Expected an orphan column failure")
        } catch {
            XCTAssertEqual(error as? RuntimeRelationCatalog.Failure, .orphanColumn(schema: "public", relation: "missing"))
        }
        XCTAssertThrowsError(try RuntimeRelationCatalog.relations(
            tables: .init(columns: ["table_schema", "table_name"], rows: [.init(values: [.primitive(.string("public")), .primitive(.string("a"))])]),
            columns: .init(columns: [], rows: []))) {
            XCTAssertEqual($0 as? RuntimeRelationCatalog.Failure, .missingColumn("table_type"))
        }
        responses = [.boolean(true)]
        do {
            _ = try await RuntimeRelationCatalog.load { _ in responses.removeFirst() }
            XCTFail("Expected a non-row response failure")
        } catch {
            XCTAssertEqual(error as? RuntimeRelationCatalog.Failure, .unexpectedResponse)
        }
    }

    func testBrowseRequestUsesQualifiedRelationAndAppliedOptions() throws {
        let relation = RuntimeRelation(schema: "sales", name: "line items", tableType: "BASE TABLE",
                                       columns: [.init(name: "qty", dataType: "bigint", isNullable: true)])
        let workspace = RuntimeRecordsWorkspace()
        workspace.sortField = "qty"
        workspace.descending = true
        workspace.pageLimit = 25
        workspace.filter = RuntimeRecordFilter(field: "qty", comparison: .isNotNull)
        let request = try workspace.request(for: relation)
        XCTAssertEqual(request.page, .init(limit: 25))
        guard case .statement(.select(let select)) = request.input else { return XCTFail("Expected a typed SELECT") }
        XCTAssertEqual(select.source, .table(TableRef(schema: "sales", table: "line items")))
        XCTAssertEqual(select.filter, .isNotNull(.column(ColumnRef("qty"))))
        XCTAssertEqual(select.orderBy, [SortKey(.column(ColumnRef("qty")), direction: .descending)])
        workspace.filter = RuntimeRecordFilter(field: "qty", comparison: .equal, valueType: .int64, text: "x")
        XCTAssertThrowsError(try workspace.request(for: relation))
    }
}
