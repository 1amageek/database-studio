import Foundation

/// A frozen, source-attributed Wikidata sample for graph presentation.
struct AutomotiveGraphSnapshot: Decodable {
    enum Failure: LocalizedError {
        case missingResource, invalidSnapshot

        var errorDescription: String? {
            switch self {
            case .missingResource: "The bundled automotive dataset is missing."
            case .invalidSnapshot: "The automotive dataset has invalid provenance, identities or relationships."
            }
        }
    }

    let source: String
    let sourceURL: String
    let license: String
    let retrievedAt: String
    let selection: String
    let labels: [String: String]
    let triples: [[String]]
    let propertyLabels: [String: String]

    static func load() throws -> GraphDocument {
        guard let url = Bundle.module.url(forResource: "automotive", withExtension: "json") else {
            throw Failure.missingResource
        }
        // Materialize once at the immutable file-to-document ownership boundary.
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> GraphDocument {
        let snapshot = try JSONDecoder().decode(Self.self, from: data)
        guard snapshot.source == "Wikidata", snapshot.sourceURL == "https://www.wikidata.org/",
              snapshot.license == "CC0-1.0", !snapshot.retrievedAt.isEmpty, !snapshot.selection.isEmpty,
              snapshot.labels.count == 1000, !snapshot.triples.isEmpty,
              snapshot.triples.count <= GraphSpatialLayout.maximumEdges,
              Set(snapshot.triples).count == snapshot.triples.count,
              snapshot.labels.allSatisfy({ $0.key.hasPrefix("http://www.wikidata.org/entity/Q") && !$0.value.isEmpty }) else {
            throw Failure.invalidSnapshot
        }
        var adjacency: [String: Set<String>] = [:]
        let relations = try snapshot.triples.map { triple -> RDFTripleData in
            guard triple.count == 3, snapshot.labels[triple[0]] != nil,
                  snapshot.labels[triple[2]] != nil, snapshot.propertyLabels[triple[1]] != nil else {
                throw Failure.invalidSnapshot
            }
            adjacency[triple[0], default: []].insert(triple[2])
            adjacency[triple[2], default: []].insert(triple[0])
            return RDFTripleData(subject: triple[0], predicate: triple[1], object: triple[2])
        }
        var visited: Set<String> = []
        var pending = ["http://www.wikidata.org/entity/Q3231690"]
        while let node = pending.popLast() {
            if visited.insert(node).inserted { pending.append(contentsOf: adjacency[node] ?? []) }
        }
        guard visited == Set(snapshot.labels.keys) else { throw Failure.invalidSnapshot }
        var document = try GraphDocument(triples: relations)
        let classes = Set(relations.filter { $0.predicate.hasSuffix("/P31") }.map(\.object))
        for index in document.nodes.indices {
            let id = document.nodes[index].id
            guard let label = snapshot.labels[id] else { throw Failure.invalidSnapshot }
            document.nodes[index].label = label
            if classes.contains(id) { document.nodes[index].role = .type }
            document.nodes[index].metadata["Source"] = snapshot.source
            document.nodes[index].metadata["Source URL"] = "https://www.wikidata.org/wiki/" + localName(id)
            document.nodes[index].metadata["Retrieved"] = snapshot.retrievedAt
            document.nodes[index].metadata["License"] = snapshot.license
            document.nodes[index].metadata["Sampling"] = snapshot.selection
            if document.nodes[index].label == localName(id) {
                document.nodes[index].metadata["Label availability"] = "No English label in the source snapshot; showing the original entity identifier."
            }
        }
        for index in document.edges.indices {
            guard let predicate = document.edges[index].ontologyProperty,
                  let label = snapshot.propertyLabels[predicate] else { throw Failure.invalidSnapshot }
            document.edges[index].label = label
            if predicate.hasSuffix("/P31") { document.edges[index].edgeKind = .instanceOf }
        }
        document.nodes.sort { $0.id < $1.id }
        return document
    }
}
