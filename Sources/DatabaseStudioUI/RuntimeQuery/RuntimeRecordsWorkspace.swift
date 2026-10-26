import Observation
import DatabaseKit
import DatabaseWire

/// Retains one selected relation's applied result and draft source options.
@Observable @MainActor
final class RuntimeRecordsWorkspace {
    let query = RuntimeQuery()
    var sortField = ""
    var descending = false
    var pageLimit = Int(QueryExecuteOperation.Page().limit)
    var filter = RuntimeRecordFilter()

    /// Builds the typed browse request from the applied options; names are catalog values, never SQL text.
    func request(for relation: RuntimeRelation) throws -> QueryExecuteOperation.Request {
        let expression = try filter.expression()
        let order = sortField.isEmpty ? nil
            : [SortKey(.column(ColumnRef(sortField)), direction: descending ? .descending : .ascending)]
        return QueryExecuteOperation.Request(input: .statement(.select(
            SelectQuery(projection: [.wildcard()], source: .table(relation.tableReference),
                        filter: expression, orderBy: order))),
            page: .init(limit: UInt32(clamping: max(0, pageLimit))))
    }
}
