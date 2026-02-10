import Foundation
import Graph

extension GraphDocument {

    /// RDFTripleData 配列からグラフドキュメントを構築する
    ///
    /// - `rdf:type` トリプル → object ノードを `.owlClass` に昇格
    /// - リテラル（`"` で始まる object）→ subject の metadata に格納（ノード化しない）
    /// - その他の object property トリプル → エッジ
    public init(triples: [RDFTripleData]) {
        var nodeMap: [String: GraphNode] = [:]
        var edges: [GraphEdge] = []
        var literalMetadata: [String: [String: String]] = [:]

        for triple in triples {
            let subjectLabel = localName(triple.subject)

            // subject ノードがなければ individual として追加
            if nodeMap[triple.subject] == nil {
                nodeMap[triple.subject] = GraphNode(
                    id: triple.subject,
                    label: subjectLabel,
                    kind: .individual
                )
            }

            let predicateLocal = localName(triple.predicate)

            // rdf:type の処理
            if triple.predicate == "rdf:type"
                || triple.predicate.hasSuffix("#type")
                || triple.predicate == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
            {
                let classLabel = localName(triple.object)
                // object を owlClass ノードとして登録（昇格）
                if var existing = nodeMap[triple.object] {
                    existing.kind = .owlClass
                    nodeMap[triple.object] = existing
                } else {
                    nodeMap[triple.object] = GraphNode(
                        id: triple.object,
                        label: classLabel,
                        kind: .owlClass
                    )
                }
                let edgeID = "\(triple.subject)-rdf:type-\(triple.object)"
                edges.append(GraphEdge(
                    id: edgeID,
                    sourceID: triple.subject,
                    targetID: triple.object,
                    label: "rdf:type"
                ))
                continue
            }

            // リテラル判定: `"` で始まる値は OWLLiteral としてパースし metadata に格納
            if triple.object.hasPrefix("\"") {
                let literal = Self.parseRDFLiteral(triple.object)
                literalMetadata[triple.subject, default: [:]][predicateLocal] = literal.lexicalForm
                continue
            }

            // object property トリプル → エッジ
            let objectLabel = localName(triple.object)
            if nodeMap[triple.object] == nil {
                nodeMap[triple.object] = GraphNode(
                    id: triple.object,
                    label: objectLabel,
                    kind: .individual
                )
            }

            let edgeID = "\(triple.subject)-\(triple.predicate)-\(triple.object)"
            edges.append(GraphEdge(
                id: edgeID,
                sourceID: triple.subject,
                targetID: triple.object,
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

    /// RDF リテラル文字列を `OWLLiteral` にパースする
    static func parseRDFLiteral(_ raw: String) -> OWLLiteral {
        guard raw.hasPrefix("\"") else {
            return .string(raw)
        }
        if let caretRange = raw.range(of: "\"^^", options: .backwards) {
            let text = String(raw[raw.index(after: raw.startIndex)..<caretRange.lowerBound])
            var datatype = String(raw[caretRange.upperBound...])
            while datatype.hasPrefix("<") && datatype.hasSuffix(">") {
                datatype = String(datatype.dropFirst().dropLast())
            }
            return OWLLiteral(lexicalForm: text, datatype: datatype)
        }
        if let atRange = raw.range(of: "\"@", options: .backwards) {
            let text = String(raw[raw.index(after: raw.startIndex)..<atRange.lowerBound])
            let lang = String(raw[atRange.upperBound...])
            return .langString(text, language: lang)
        }
        if raw.hasSuffix("\"") {
            let text = String(raw.dropFirst().dropLast())
            return .string(text)
        }
        return .string(raw)
    }
}
