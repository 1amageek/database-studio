import DatabaseWire

extension RuntimeConnection: RuntimeQueryExecuting {
    func executeQuery(_ request: QueryExecuteOperation.Request) async throws -> QueryExecuteOperation.Response {
        try await execute(DatabaseOperationCatalog.queryExecute, request: request)
    }
}
