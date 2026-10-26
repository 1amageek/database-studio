import Foundation
import DatabaseKit
import DatabaseWire

/// Loads the relation catalog from information_schema through the canonical query operation,
/// on the same MainActor isolation as RuntimeQueryExecuting.
@MainActor
enum RuntimeRelationCatalog {
    enum Failure: Error, LocalizedError, Equatable {
        case unexpectedResponse
        case missingColumn(String)
        case invalidValue(column: String)
        case orphanColumn(schema: String, relation: String)

        var errorDescription: String? {
            switch self {
            case .unexpectedResponse: "The server returned a non-row or paged SQL catalog response."
            case .missingColumn(let name): "The SQL catalog response has no \(name) column."
            case .invalidValue(let column): "The SQL catalog returned a non-text \(column) value."
            case .orphanColumn(let schema, let relation): "The SQL catalog lists columns for unknown relation \(schema).\(relation)."
            }
        }
    }

    static let tablesStatement = "SELECT table_schema, table_name, table_type FROM information_schema.tables ORDER BY table_schema, table_name"
    static let columnsStatement = "SELECT table_schema, table_name, column_name, data_type, is_nullable FROM information_schema.columns ORDER BY table_schema, table_name, ordinal_position"

    static func load(
        _ execute: (QueryExecuteOperation.Request) async throws -> QueryExecuteOperation.Response
    ) async throws -> [RuntimeRelation] {
        let budget = ExecutionBudget()
        let tables = try rows(await execute(.init(input: .sql(tablesStatement), budget: budget)), budget: budget)
        try Task.checkCancellation()
        let columns = try rows(await execute(.init(input: .sql(columnsStatement), budget: budget)), budget: budget)
        return try relations(tables: tables, columns: columns)
    }

    static func relations(tables: NamedRows, columns: NamedRows) throws -> [RuntimeRelation] {
        var columnsByRelation: [RuntimeRelation.ID: [RuntimeRelation.Column]] = [:]
        for row in columns.rows {
            let id = RuntimeRelation.ID(schema: try columns.text(row, "table_schema"), name: try columns.text(row, "table_name"))
            columnsByRelation[id, default: []].append(.init(name: try columns.text(row, "column_name"),
                dataType: try columns.text(row, "data_type"), isNullable: try columns.text(row, "is_nullable") == "YES"))
        }
        var relations: [RuntimeRelation] = []
        relations.reserveCapacity(tables.rows.count)
        for row in tables.rows {
            let schema = try tables.text(row, "table_schema"), name = try tables.text(row, "table_name")
            relations.append(.init(schema: schema, name: name, tableType: try tables.text(row, "table_type"),
                columns: columnsByRelation.removeValue(forKey: .init(schema: schema, name: name)) ?? []))
        }
        if let orphan = columnsByRelation.keys.first {
            throw Failure.orphanColumn(schema: orphan.schema, relation: orphan.name)
        }
        return relations
    }

    /// Rows addressed by result column name, so decoding does not depend on projection order.
    struct NamedRows {
        let indices: [String: Int]
        let rows: [DatabaseKit.QueryRow]

        init(columns: [String], rows: [DatabaseKit.QueryRow]) {
            var indices: [String: Int] = [:]
            for (index, name) in columns.enumerated() where indices[name] == nil { indices[name] = index }
            self.indices = indices
            self.rows = rows
        }

        func text(_ row: DatabaseKit.QueryRow, _ column: String) throws -> String {
            guard let index = indices[column], row.values.indices.contains(index) else { throw Failure.missingColumn(column) }
            guard case .primitive(.string(let value)) = row.values[index] else { throw Failure.invalidValue(column: column) }
            return value
        }
    }

    private static func rows(_ response: QueryExecuteOperation.Response, budget: ExecutionBudget) throws -> NamedRows {
        guard response.results.count == 1, case .rows(let page) = response, page.continuation == nil else {
            throw Failure.unexpectedResponse
        }
        return NamedRows(columns: page.columns.map(\.name),
            rows: try page.materializedRows(maximumCount: Int(budget.maximumRows)))
    }
}
