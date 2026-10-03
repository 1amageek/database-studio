import Observation
import DatabaseWire

/// Retains one selected entity's applied result and draft source options.
@Observable @MainActor
final class RuntimeRecordsWorkspace {
    let query = RuntimeQuery()
    var sortField = ""
    var descending = false
    var pageLimit = Int(QueryExecuteOperation.Page().limit)
    var filter = RuntimeRecordFilter()
}
