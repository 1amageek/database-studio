import DatabaseKit

/// Projects one named graph from a bounded canonical result page.
struct RuntimeGraphPage {
    enum ProjectionError: Error {
        case unsupportedTripleTerm
    }

    let quads: [RDFQuad]

    func document(in graph: RDFGraphName?) throws -> GraphDocument {
        var nodes: [String: GraphNode] = [:]
        var edges: [GraphEdge] = []
        let typeIRI = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        let subclassIRI = "http://www.w3.org/2000/01/rdf-schema#subClassOf"

        func identity(_ term: RDFTerm) throws -> String {
            switch term {
            case .iri(let iri): return iri.rawValue
            case .blankNode: return term.description
            case .literal: return term.description
            // FIXME(INCOMPLETE_IMPLEMENTATION): Quoted triple nodes have no graph glyph yet.
            // Runtime result graph projection rejects them; preserve nested term identity
            // and verify selection/inspection before enabling this presentation path.
            case .tripleTerm: throw ProjectionError.unsupportedTripleTerm
            }
        }

        for (offset, quad) in quads.enumerated() where quad.graph == graph {
            let subject = try identity(quad.subject.term)
            let predicate = quad.predicate.rawValue
            if nodes[subject] == nil {
                nodes[subject] = GraphNode(id: subject, label: localName(subject), role: .instance)
            }
            if case .literal(let literal) = quad.object {
                let previous = nodes[subject]?.metadata[predicate]
                nodes[subject]?.metadata[predicate] = previous.map { $0 + "\n" + literal.description } ?? literal.description
                continue
            }
            let object = try identity(quad.object)
            if nodes[object] == nil {
                nodes[object] = GraphNode(id: object, label: localName(object), role: .instance)
            }
            let kind: GraphEdgeKind
            if predicate == typeIRI {
                nodes[object]?.role = .type
                nodes[object]?.ontologyClass = object
                kind = .instanceOf
            } else if predicate == subclassIRI {
                nodes[subject]?.role = .type
                nodes[subject]?.ontologyClass = subject
                nodes[object]?.role = .type
                nodes[object]?.ontologyClass = object
                kind = .subClassOf
            } else {
                kind = .relationship
            }
            edges.append(GraphEdge(id: String(offset), sourceID: subject, targetID: object,
                label: localName(predicate), ontologyProperty: predicate, edgeKind: kind))
        }
        return GraphDocument(nodes: nodes.values.sorted { $0.id < $1.id }, edges: edges)
    }
}
