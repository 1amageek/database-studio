import Foundation
import Core
import Graph

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
        var literalMetadata: [String: [String: String]] = [:]

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

            // エッジラベル
            let edgeLabel: String
            if edgeField.isEmpty {
                edgeLabel = graphIndex.name
            } else {
                edgeLabel = item.fields[edgeField] as? String ?? ""
            }

            let predicateLocal = localName(edgeLabel)

            // リテラル判定: `"` で始まる値は metadata に格納（ノード化しない）
            if toValue.hasPrefix("\"") {
                let literal = Self.parseRDFLiteral(toValue)
                literalMetadata[fromValue, default: [:]][predicateLocal] = literal.lexicalForm
                continue
            }

            // to ノード
            if nodeMap[toValue] == nil {
                nodeMap[toValue] = GraphNode(
                    id: toValue,
                    label: localName(toValue),
                    kind: .individual
                )
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
                label: predicateLocal
            ))
        }

        // リテラル metadata をノードに反映
        for (nodeID, meta) in literalMetadata {
            if var node = nodeMap[nodeID] {
                node.metadata.merge(meta) { _, new in new }
                nodeMap[nodeID] = node
            }
        }

        self.nodes = Array(nodeMap.values)
        self.edges = edges
    }
}
