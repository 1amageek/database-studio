import Foundation

struct GraphClusterConfiguration: Equatable, Sendable {
    enum Mode: String, CaseIterable, Sendable { case graph = "Graph Features", numeric = "Numeric Data" }
    enum Projection: String, CaseIterable, Sendable { case axes = "Selected Axes", pca = "PCA" }
    var mode: Mode = .graph
    var role: GraphNodeRole = .instance
    var clusterCount = 8
    var typeWeight: Double = 1
    var relationshipWeight: Double = 1
    var attributeWeight: Double = 1
    var metadataKeys: Set<String> = []
    var metricKeys: Set<String> = []
    var numericFeatures: [GraphNumericFeature] = []
    var comparisonKey: String?
    var layerKey: String?
    var projection: Projection = .axes
    var xFeatureID: String?
    var yFeatureID: String?
    var excludesFlaggedRows = true
}
