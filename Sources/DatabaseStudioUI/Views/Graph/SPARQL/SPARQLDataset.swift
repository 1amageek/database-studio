/// A queryable RDF triple projected from a graph document.
struct RDFTriple: Sendable {
    let subject: String
    let predicate: String
    let object: String
}

/// The SPARQL dataset projected from a graph document.
struct SPARQLDataset: Sendable {

    private let triples: [RDFTriple]
    private let subjectIndex: [String: [Int]]
    private let predicateIndex: [String: [Int]]
    private let objectIndex: [String: [Int]]
    private let spIndex: [String: [Int]]

    /// Projects queryable triples and lookup indexes from a graph document.
    init(document: GraphDocument) {
        var allTriples: [RDFTriple] = []
        allTriples.reserveCapacity(document.edges.count + document.nodes.count * 2)

        // Project graph edges into RDF triples.
        for edge in document.edges {
            let predicate = edge.ontologyProperty ?? edge.label
            allTriples.append(RDFTriple(
                subject: edge.sourceID,
                predicate: predicate,
                object: edge.targetID
            ))
        }

        // Project node metadata into RDF triples.
        for node in document.nodes {
            for (key, value) in node.metadata {
                allTriples.append(RDFTriple(
                    subject: node.id,
                    predicate: key,
                    object: "\"\(value)\""
                ))
            }
            // Expose each visible node label to SPARQL queries.
            allTriples.append(RDFTriple(
                subject: node.id,
                predicate: "rdfs:label",
                object: "\"\(node.label)\""
            ))
        }

        self.triples = allTriples

        var subjectEntries: [String: [Int]] = [:]
        var predicateEntries: [String: [Int]] = [:]
        var objectEntries: [String: [Int]] = [:]
        var subjectPredicateEntries: [String: [Int]] = [:]

        for (tripleOffset, triple) in allTriples.enumerated() {
            subjectEntries[triple.subject, default: []].append(tripleOffset)
            predicateEntries[triple.predicate, default: []].append(tripleOffset)
            objectEntries[triple.object, default: []].append(tripleOffset)
            subjectPredicateEntries[
                Self.subjectPredicateKey(subject: triple.subject, predicate: triple.predicate),
                default: []
            ].append(tripleOffset)
        }

        self.subjectIndex = subjectEntries
        self.predicateIndex = predicateEntries
        self.objectIndex = objectEntries
        self.spIndex = subjectPredicateEntries
    }

    /// Matches triples, treating a missing term as a wildcard.
    func match(subject: String?, predicate: String?, object: String?) -> [RDFTriple] {
        let candidateOffsets: [Int]

        switch (subject, predicate, object) {
        case let (subject?, predicate?, _):
            candidateOffsets = spIndex[
                Self.subjectPredicateKey(subject: subject, predicate: predicate)
            ] ?? []
        case let (subject?, _, _):
            candidateOffsets = subjectIndex[subject] ?? []
        case let (_, predicate?, _):
            candidateOffsets = predicateIndex[predicate] ?? []
        case let (_, _, object?):
            candidateOffsets = objectIndex[object] ?? []
        case (nil, nil, nil):
            return triples
        }

        return candidateOffsets.compactMap { tripleOffset in
            let triple = triples[tripleOffset]
            if let subject, triple.subject != subject { return nil }
            if let predicate, triple.predicate != predicate { return nil }
            if let object, triple.object != object { return nil }
            return triple
        }
    }

    /// The total number of triples in the dataset.
    var count: Int { triples.count }

    // MARK: - Composite Lookup Keys

    private static func subjectPredicateKey(subject: String, predicate: String) -> String {
        "\(subject)\0\(predicate)"
    }
}
