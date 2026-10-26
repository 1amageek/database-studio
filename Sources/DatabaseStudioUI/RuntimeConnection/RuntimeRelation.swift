import DatabaseKit
import DatabaseWire

/// One SQL relation visible to the authenticated principal, named by the SQL catalog.
///
/// These names, not storage entity names from schema.describe, resolve in SQL.
struct RuntimeRelation: Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        let schema: String
        let name: String
    }

    struct Column: Hashable, Sendable {
        let name: String
        let dataType: String
        let isNullable: Bool
    }

    let schema: String
    let name: String
    let tableType: String
    let columns: [Column]

    var id: ID { ID(schema: schema, name: name) }

    /// Qualified so resolution never depends on the caller's search path.
    var tableReference: TableRef { TableRef(schema: schema, table: name) }
}
