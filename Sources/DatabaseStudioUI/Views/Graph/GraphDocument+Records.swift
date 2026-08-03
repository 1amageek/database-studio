import Foundation
import DatabaseKit
import DatabaseKit

extension GraphDocument {

    /// Builds a graph document from Studio records and GraphIndex metadata.
    ///
    /// Resolves the configured source, edge, and target fields and transforms
    /// each record into graph nodes and edges.
    init(records: [StudioRecord], graphIndex: IndexDescriptorMetadata) throws {
        let indexMetadata = graphIndex.kind.metadata
        let fromField = indexMetadata["fromField"]?.stringValue ?? ""
        let edgeField = indexMetadata["edgeField"]?.stringValue ?? ""
        let toField = indexMetadata["toField"]?.stringValue ?? ""

        var nodesByIdentifier: [String: GraphNode] = [:]
        var edges: [GraphEdge] = []
        var literalMetadata: [String: [String: String]] = [:]

        for record in records {
            guard let fromValue = record.fields[fromField] as? String,
                  let toValue = record.fields[toField] as? String else {
                continue
            }

            // from ノード
            if nodesByIdentifier[fromValue] == nil {
                nodesByIdentifier[fromValue] = GraphNode(
                    id: fromValue,
                    label: localName(fromValue),
                    role: .instance,
                    source: .graphIndex
                )
            }

            // エッジラベル
            let edgeLabel: String
            if edgeField.isEmpty {
                edgeLabel = graphIndex.name
            } else {
                edgeLabel = record.fields[edgeField] as? String ?? ""
            }

            let predicateLocal = localName(edgeLabel)

            // リテラル判定: `"` で始まる値は metadata に格納（ノード化しない）
            if toValue.hasPrefix("\"") {
                let literal = try Self.parseRDFLiteral(toValue)
                literalMetadata[fromValue, default: [:]][predicateLocal] = literal.lexicalForm
                continue
            }

            // to ノード
            if nodesByIdentifier[toValue] == nil {
                nodesByIdentifier[toValue] = GraphNode(
                    id: toValue,
                    label: localName(toValue),
                    role: .instance,
                    source: .graphIndex
                )
            }

            // rdf:type の場合、to ノードを .type ロールに昇格
            let isRdfType = edgeLabel == "rdf:type"
                || edgeLabel.hasSuffix("#type")
                || edgeLabel == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
            if isRdfType {
                if var node = nodesByIdentifier[toValue] {
                    node.role = .type
                    node.ontologyClass = toValue
                    nodesByIdentifier[toValue] = node
                }
                // from ノードに ontologyClass を設定
                if var node = nodesByIdentifier[fromValue] {
                    node.ontologyClass = toValue
                    nodesByIdentifier[fromValue] = node
                }
            }

            // subClassOf の場合、両端をクラスに昇格（case-insensitive）
            let isSubClassOf = predicateLocal.lowercased() == "subclassof"
            if isSubClassOf {
                if var node = nodesByIdentifier[fromValue], node.role != .type {
                    node.role = .type
                    node.ontologyClass = fromValue
                    nodesByIdentifier[fromValue] = node
                }
                if var node = nodesByIdentifier[toValue], node.role != .type {
                    node.role = .type
                    node.ontologyClass = toValue
                    nodesByIdentifier[toValue] = node
                }
            }

            let edgeKind: GraphEdgeKind = isRdfType ? .instanceOf : (isSubClassOf ? .subClassOf : .relationship)
            edges.append(GraphEdge(
                id: record.id,
                sourceID: fromValue,
                targetID: toValue,
                label: predicateLocal,
                ontologyProperty: edgeLabel,
                edgeKind: edgeKind
            ))
        }

        // リテラル metadata をノードに反映
        for (nodeIdentifier, metadata) in literalMetadata {
            if var node = nodesByIdentifier[nodeIdentifier] {
                node.metadata.merge(metadata) { _, newValue in newValue }
                nodesByIdentifier[nodeIdentifier] = node
            }
        }

        self.nodes = Array(nodesByIdentifier.values)
        self.edges = edges
    }
}
