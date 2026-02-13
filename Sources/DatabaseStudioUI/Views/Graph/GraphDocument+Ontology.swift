import Foundation
import Graph

extension GraphDocument {

    /// OWLOntology からグラフドキュメントを構築する
    ///
    /// - `ontology.classes` → `.type` ノード
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
                role: .type,
                ontologyClass: cls.iri,
                source: .ontology,
                metadata: cls.comment.map { ["comment": $0] } ?? [:]
            )
        }

        // Axiom → エッジ
        for axiom in ontology.axioms {
            switch axiom {
            case .subClassOf(let sub, let sup):
                guard case .named(let subIRI) = sub,
                      case .named(let supIRI) = sup else { continue }
                ensureNode(iri: subIRI, role: .type, source: .ontology, in: &nodeMap)
                ensureNode(iri: supIRI, role: .type, source: .ontology, in: &nodeMap)
                edges.append(GraphEdge(
                    id: "subClassOf-\(subIRI)-\(supIRI)",
                    sourceID: subIRI,
                    targetID: supIRI,
                    label: "subClassOf",
                    edgeKind: .subClassOf
                ))

            case .equivalentClasses(let expressions):
                let namedIRIs = expressions.compactMap { expr -> String? in
                    if case .named(let iri) = expr { return iri }
                    return nil
                }
                for i in 0..<namedIRIs.count {
                    for j in (i + 1)..<namedIRIs.count {
                        ensureNode(iri: namedIRIs[i], role: .type, source: .ontology, in: &nodeMap)
                        ensureNode(iri: namedIRIs[j], role: .type, source: .ontology, in: &nodeMap)
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
                    ensureNode(iri: domainIRI, role: .type, source: .ontology, in: &nodeMap)
                    ensureNode(iri: rangeIRI, role: .type, source: .ontology, in: &nodeMap)
                    edges.append(GraphEdge(
                        id: "objProp-\(prop.iri)-\(domainIRI)-\(rangeIRI)",
                        sourceID: domainIRI,
                        targetID: rangeIRI,
                        label: propLabel,
                        ontologyProperty: prop.iri,
                        edgeKind: .property
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

extension GraphDocument {

    /// 既存ドキュメントに OWLOntology のクラス定義と subClassOf エッジをマージする
    ///
    /// RDF データから構築したドキュメントに ontology の階層情報を追加することで、
    /// サイドバーのクラスツリーに subClassOf 関係を反映させる。
    public mutating func mergeOntology(_ ontology: OWLOntology) {
        var nodeMap: [String: GraphNode] = Dictionary(
            uniqueKeysWithValues: nodes.map { ($0.id, $0) }
        )

        // Ontology クラスをマージ（既存ノードがあれば metadata を補完、なければ追加）
        for cls in ontology.classes {
            let iri = cls.iri
            let label = cls.label ?? localName(iri)
            if var existing = nodeMap[iri] {
                existing.role = .type
                if let comment = cls.comment {
                    existing.metadata["comment"] = comment
                }
                nodeMap[iri] = existing
            } else {
                nodeMap[iri] = GraphNode(
                    id: iri,
                    label: label,
                    role: .type,
                    ontologyClass: iri,
                    source: .ontology,
                    metadata: cls.comment.map { ["comment": $0] } ?? [:]
                )
            }
        }

        // subClassOf エッジをマージ（重複チェック）
        var existingEdgeIDs = Set(edges.map(\.id))
        for axiom in ontology.axioms {
            if case .subClassOf(let sub, let sup) = axiom,
               case .named(let subIRI) = sub,
               case .named(let supIRI) = sup {
                let edgeID = "subClassOf-\(subIRI)-\(supIRI)"
                guard !existingEdgeIDs.contains(edgeID) else { continue }
                existingEdgeIDs.insert(edgeID)

                if nodeMap[subIRI] == nil {
                    nodeMap[subIRI] = GraphNode(
                        id: subIRI, label: localName(subIRI),
                        role: .type, ontologyClass: subIRI, source: .ontology
                    )
                }
                if nodeMap[supIRI] == nil {
                    nodeMap[supIRI] = GraphNode(
                        id: supIRI, label: localName(supIRI),
                        role: .type, ontologyClass: supIRI, source: .ontology
                    )
                }

                edges.append(GraphEdge(
                    id: edgeID,
                    sourceID: subIRI,
                    targetID: supIRI,
                    label: "subClassOf",
                    edgeKind: .subClassOf
                ))
            }
        }

        nodes = Array(nodeMap.values)
    }
}

private func ensureNode(iri: String, role: GraphNodeRole, source: GraphNodeSource = .graphIndex, in nodeMap: inout [String: GraphNode]) {
    if nodeMap[iri] == nil {
        nodeMap[iri] = GraphNode(
            id: iri,
            label: localName(iri),
            role: role,
            ontologyClass: role == .type ? iri : nil,
            source: source
        )
    }
}
