import DatabaseWire

/// Invokes the canonical query operation without owning presentation or transport.
@MainActor
protocol RuntimeQueryExecuting {
    func executeQuery(_ request: QueryExecuteOperation.Request) async throws -> QueryExecuteOperation.Response
}
