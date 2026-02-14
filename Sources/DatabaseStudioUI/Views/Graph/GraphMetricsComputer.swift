import Foundation

/// インメモリグラフメトリクス計算（FDB 非依存）
///
/// - Degree centrality
enum GraphMetricsComputer {

    struct Result: Sendable {
        let degree: [String: Double]
    }

    /// GraphDocument からメトリクスを一括計算
    static func compute(document: GraphDocument) -> Result {
        let nodes = document.nodes
        let edges = document.edges
        guard !nodes.isEmpty else {
            return Result(degree: [:])
        }

        let nodeIDs = nodes.map(\.id)
        let nodeIDSet = Set(nodeIDs)

        // 隣接リスト構築
        var outCount: [String: Int] = [:]
        var inCount: [String: Int] = [:]

        for id in nodeIDs {
            outCount[id] = 0
            inCount[id] = 0
        }

        for edge in edges {
            guard nodeIDSet.contains(edge.sourceID), nodeIDSet.contains(edge.targetID) else { continue }
            outCount[edge.sourceID, default: 0] += 1
            inCount[edge.targetID, default: 0] += 1
        }

        var degree: [String: Double] = [:]
        degree.reserveCapacity(nodeIDs.count)
        for id in nodeIDs {
            degree[id] = Double((outCount[id] ?? 0) + (inCount[id] ?? 0))
        }

        return Result(degree: degree)
    }
}
