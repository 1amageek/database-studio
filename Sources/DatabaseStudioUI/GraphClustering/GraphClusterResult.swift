import Foundation

struct GraphClusterResult: Sendable {
    struct Cluster: Identifiable, Sendable {
        let id: Int
        let members: [String]
        let center: SIMD2<Double>
        let features: [String]
    }

    let configuration: GraphClusterConfiguration
    let clusters: [Cluster]
    let membership: [String: Int]
    let positions: [String: SIMD2<Double>]
    let unpositionedIDs: Set<String>
    let unassignedIDs: Set<String>
    let featureCount: Int
    let retainedVariance: Double
    let iterations: Int
    var axes: [GraphAnalysisAxis] = []
    var exclusionReasons: [String: String] = [:]
    var profiles: [Int: [FeatureProfile]] = [:]

    struct FeatureProfile: Identifiable, Sendable {
        let id: String
        let title: String
        let median: Double
        let lowerQuartile: Double
        let upperQuartile: Double
        let populationMedian: Double
    }
}
