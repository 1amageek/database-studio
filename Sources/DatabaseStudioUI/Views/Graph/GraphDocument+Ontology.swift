import Foundation
import Graph

extension GraphDocument {

    /// OWLOntology からグラフドキュメントを構築する
    ///
    /// - `ontology.classes` → `.owlClass` ノード
    /// - `.subClassOf` axiom → `subClassOf` エッジ
    /// - `.equivalentClasses` axiom → `equivalentTo` エッジ
    /// - `ontology.objectProperties` → domain→range エッジ
    /// - `ontology.dataProperties` → domain ノードの metadata に格納
    public init(ontology: OWLOntology) {
        var nodeMap: [String: GraphNode] = [:]
        var edges: [GraphEdge] = []

        // クラス → ノード
        for cls in ontology.classes {
            let label = cls.label ?? localName(cls.iri)
            nodeMap[cls.iri] = GraphNode(
                id: cls.iri,
                label: label,
                kind: .owlClass,
                metadata: cls.comment.map { ["comment": $0] } ?? [:]
            )
        }

        // Axiom → エッジ
        for axiom in ontology.axioms {
            switch axiom {
            case .subClassOf(let sub, let sup):
                guard case .named(let subIRI) = sub,
                      case .named(let supIRI) = sup else { continue }
                ensureNode(iri: subIRI, kind: .owlClass, in: &nodeMap)
                ensureNode(iri: supIRI, kind: .owlClass, in: &nodeMap)
                edges.append(GraphEdge(
                    id: "subClassOf-\(subIRI)-\(supIRI)",
                    sourceID: subIRI,
                    targetID: supIRI,
                    label: "subClassOf"
                ))

            case .equivalentClasses(let expressions):
                let namedIRIs = expressions.compactMap { expr -> String? in
                    if case .named(let iri) = expr { return iri }
                    return nil
                }
                for i in 0..<namedIRIs.count {
                    for j in (i + 1)..<namedIRIs.count {
                        ensureNode(iri: namedIRIs[i], kind: .owlClass, in: &nodeMap)
                        ensureNode(iri: namedIRIs[j], kind: .owlClass, in: &nodeMap)
                        edges.append(GraphEdge(
                            id: "equivalentTo-\(namedIRIs[i])-\(namedIRIs[j])",
                            sourceID: namedIRIs[i],
                            targetID: namedIRIs[j],
                            label: "equivalentTo"
                        ))
                    }
                }

            default:
                break
            }
        }

        // Object Properties → エッジ (domain → range)
        for prop in ontology.objectProperties {
            let propLabel = prop.label ?? localName(prop.iri)

            for domain in prop.domains {
                guard case .named(let domainIRI) = domain else { continue }
                for range in prop.ranges {
                    guard case .named(let rangeIRI) = range else { continue }
                    ensureNode(iri: domainIRI, kind: .owlClass, in: &nodeMap)
                    ensureNode(iri: rangeIRI, kind: .owlClass, in: &nodeMap)
                    edges.append(GraphEdge(
                        id: "objProp-\(prop.iri)-\(domainIRI)-\(rangeIRI)",
                        sourceID: domainIRI,
                        targetID: rangeIRI,
                        label: propLabel
                    ))
                }
            }
        }

        // Data Properties → domain ノードの metadata に格納
        for prop in ontology.dataProperties {
            let propLabel = prop.label ?? localName(prop.iri)
            for domain in prop.domains {
                guard case .named(let domainIRI) = domain else { continue }
                if var node = nodeMap[domainIRI] {
                    let rangeDesc = prop.ranges.map { "\($0)" }.joined(separator: ", ")
                    node.metadata["dp:\(propLabel)"] = rangeDesc.isEmpty ? "Literal" : rangeDesc
                    nodeMap[domainIRI] = node
                }
            }
        }

        self.nodes = Array(nodeMap.values)
        self.edges = edges
    }
}

private func ensureNode(iri: String, kind: GraphNodeKind, in nodeMap: inout [String: GraphNode]) {
    if nodeMap[iri] == nil {
        nodeMap[iri] = GraphNode(
            id: iri,
            label: localName(iri),
            kind: kind
        )
    }
}
