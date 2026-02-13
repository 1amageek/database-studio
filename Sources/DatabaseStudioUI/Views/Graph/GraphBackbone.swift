import Foundation

/// Backbone ノード選択: 各コミュニティの代表ノードを選出
enum GraphBackbone {

    /// メトリクス結果から backbone ノード ID を選択
    ///
    /// - 小規模グラフ（< 50 ノード）では全ノードを返す
    /// - 各コミュニティから PageRank 上位 K ノードを選択
    /// - `.type` ロール（クラス定義）は常に含める
    static func selectBackboneNodes(
        document: GraphDocument,
        metrics: GraphMetricsComputer.Result
    ) -> Set<String> {
        let nodes = document.nodes
        guard nodes.count >= 50 else {
            return Set(nodes.map(\.id))
        }

        var selected = Set<String>()

        // .type ロールのノードは常に含める
        for node in nodes where node.role == .type {
            selected.insert(node.id)
        }

        // コミュニティ別にグルーピング
        var communities: [Int: [String]] = [:]
        for node in nodes {
            let cid = metrics.communityID[node.id] ?? 0
            communities[cid, default: []].append(node.id)
        }

        let communityCount = max(1, communities.count)
        let targetTotal = min(200, max(30, nodes.count / 5))
        let k = max(2, targetTotal / communityCount)

        // 各コミュニティの PageRank 上位 K ノードを選択
        for (_, memberIDs) in communities {
            let sorted = memberIDs.sorted { id1, id2 in
                (metrics.pageRank[id1] ?? 0) > (metrics.pageRank[id2] ?? 0)
            }
            for id in sorted.prefix(k) {
                selected.insert(id)
            }
        }

        return selected
    }
}
