import Foundation

/// Backbone ノード選択: degree 上位の代表ノードを選出
enum GraphBackbone {

    /// メトリクス結果から backbone ノード ID を選択
    ///
    /// - 小規模グラフ（< 50 ノード）では全ノードを返す
    /// - `.type` ロール（クラス定義）は常に含める
    /// - degree 上位 K ノードを選択
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

        let targetTotal = min(200, max(30, nodes.count / 5))

        // degree 上位ノードを選択
        let sorted = nodes.sorted { id1, id2 in
            (metrics.degree[id1.id] ?? 0) > (metrics.degree[id2.id] ?? 0)
        }
        for node in sorted.prefix(targetTotal) {
            selected.insert(node.id)
        }

        return selected
    }
}
