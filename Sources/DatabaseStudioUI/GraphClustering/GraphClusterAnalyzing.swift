protocol GraphClusterAnalyzing: Sendable {
    func analyze(document: GraphDocument, configuration: GraphClusterConfiguration) async throws -> GraphClusterResult
}
