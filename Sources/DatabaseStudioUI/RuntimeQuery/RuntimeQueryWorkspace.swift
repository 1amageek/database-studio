import DatabaseKit
import Observation
import DatabaseWire

/// Retains the query editor and applied result for one connected workspace.
@Observable @MainActor
final class RuntimeQueryWorkspace {
    let query = RuntimeQuery()
    let mutation = RuntimeMutation()
    var statement = ""
    var language = QueryLanguage.sql
    var isMutation = false
}
