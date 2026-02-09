import Foundation
import Core

extension GraphDocument {

    /// DecodedItem 配列と GraphIndex メタデータからグラフドキュメントを構築する
    ///
    /// GraphIndexKind の metadata から from/edge/to フィールドを取得し、
    /// 各 item のフィールド値をノード・エッジに変換する。
    init(items: [DecodedItem], graphIndex: AnyIndexDescriptor) {
        let meta = graphIndex.kind.metadata
        let fromField = meta["fromField"]?.stringValue ?? ""
        let edgeField = meta["edgeField"]?.stringValue ?? ""
        let toField = meta["toField"]?.stringValue ?? ""

        var nodeMap: [String: GraphNode] = [:]
        var edges: [GraphEdge] = []

        for item in items {
            guard let fromValue = item.fields[fromField] as? String,
                  let toValue = item.fields[toField] as? String else {
                continue
            }

            // from ノード
            if nodeMap[fromValue] == nil {
                nodeMap[fromValue] = GraphNode(
                    id: fromValue,
                    label: localName(fromValue),
                    kind: .individual
                )
            }

            // to ノード
            if nodeMap[toValue] == nil {
                nodeMap[toValue] = GraphNode(
                    id: toValue,
                    label: localName(toValue),
                    kind: .individual
                )
            }

            // エッジ
            let edgeLabel: String
            if edgeField.isEmpty {
                edgeLabel = graphIndex.name
            } else {
                edgeLabel = item.fields[edgeField] as? String ?? ""
            }

            // rdf:type の場合、to ノードを owlClass に昇格
            if edgeLabel == "rdf:type"
                || edgeLabel.hasSuffix("#type")
                || edgeLabel == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" {
                if var node = nodeMap[toValue] {
                    node.kind = .owlClass
                    nodeMap[toValue] = node
                }
            }

            edges.append(GraphEdge(
                id: item.id,
                sourceID: fromValue,
                targetID: toValue,
                label: localName(edgeLabel)
            ))
        }

        self.nodes = Array(nodeMap.values)
        self.edges = edges
    }
}
