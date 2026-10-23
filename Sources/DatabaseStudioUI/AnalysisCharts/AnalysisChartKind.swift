import Foundation

enum AnalysisChartKind: String, CaseIterable, Sendable {
    case scatter = "Scatter"
    case counts = "Cluster Counts"
    case profiles = "Feature Profiles"
}
