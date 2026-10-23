import Foundation

protocol AnalysisChartProjecting: Sendable {
    func project(_ result: GraphClusterResult, rowCount: Int) async throws -> AnalysisChartData
}
