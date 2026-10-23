import Foundation

struct AnalysisChartData: Sendable {
    struct Point: Identifiable, Sendable {
        let id: Int
        let x: Double
        let y: Double
        let clusterID: Int
        var clusterLabel: String { "Cluster \(clusterID + 1)" }
    }

    struct Group: Identifiable, Sendable {
        let id: Int
        let rowIDs: [Int]
        var label: String { "Cluster \(id + 1)" }
    }

    struct Profile: Identifiable, Sendable {
        let id: Int
        let median: Double
        let lowerQuartile: Double
        let upperQuartile: Double
        var clusterLabel: String { "Cluster \(id + 1)" }
    }

    struct Feature: Identifiable, Sendable {
        let id: String
        let title: String
        let populationMedian: Double
        let profiles: [Profile]
    }

    let points: [Point]
    let groups: [Group]
    let features: [Feature]
    let xTitle: String
    let yTitle: String
    let projectionDescription: String
    let excludedCount: Int
}
