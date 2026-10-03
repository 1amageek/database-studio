import Foundation

struct GraphClusterConfiguration: Equatable, Sendable {
    var role: GraphNodeRole = .instance
    var clusterCount = 8
    var typeWeight: Double = 1
    var relationshipWeight: Double = 1
    var attributeWeight: Double = 1
    var metadataKeys: Set<String> = []
    var metricKeys: Set<String> = []
}
