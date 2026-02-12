/// RDF トリプルの軽量表現
struct RDFTriple: Sendable {
    let subject: String
    let predicate: String
    let object: String
}

/// GraphDocument からトリプルを再構成し、インデックス付きで保持するストア
struct InMemoryTripleStore: Sendable {

    private let triples: [RDFTriple]
    private let subjectIndex: [String: [Int]]
    private let predicateIndex: [String: [Int]]
    private let objectIndex: [String: [Int]]
    private let spIndex: [String: [Int]]

    /// GraphDocument から構築
    init(document: GraphDocument) {
        var allTriples: [RDFTriple] = []
        allTriples.reserveCapacity(document.edges.count + document.nodes.count * 2)

        // エッジ → トリプル
        for edge in document.edges {
            let predicate = edge.ontologyProperty ?? edge.label
            allTriples.append(RDFTriple(
                subject: edge.sourceID,
                predicate: predicate,
                object: edge.targetID
            ))
        }

        // ノードメタデータ → トリプル
        for node in document.nodes {
            for (key, value) in node.metadata {
                allTriples.append(RDFTriple(
                    subject: node.id,
                    predicate: key,
                    object: "\"\(value)\""
                ))
            }
            // rdfs:label トリプル
            allTriples.append(RDFTriple(
                subject: node.id,
                predicate: "rdfs:label",
                object: "\"\(node.label)\""
            ))
        }

        self.triples = allTriples

        // インデックス構築
        var sIdx: [String: [Int]] = [:]
        var pIdx: [String: [Int]] = [:]
        var oIdx: [String: [Int]] = [:]
        var spIdx: [String: [Int]] = [:]

        for (i, triple) in allTriples.enumerated() {
            sIdx[triple.subject, default: []].append(i)
            pIdx[triple.predicate, default: []].append(i)
            oIdx[triple.object, default: []].append(i)
            spIdx[Self.spKey(triple.subject, triple.predicate), default: []].append(i)
        }

        self.subjectIndex = sIdx
        self.predicateIndex = pIdx
        self.objectIndex = oIdx
        self.spIndex = spIdx
    }

    /// パターンマッチ（nil = ワイルドカード）
    func match(subject: String?, predicate: String?, object: String?) -> [RDFTriple] {
        let candidates: [Int]

        switch (subject, predicate, object) {
        case let (s?, p?, _):
            // subject + predicate が最も選択的
            candidates = spIndex[Self.spKey(s, p)] ?? []
        case let (s?, _, _):
            candidates = subjectIndex[s] ?? []
        case let (_, p?, _):
            candidates = predicateIndex[p] ?? []
        case let (_, _, o?):
            candidates = objectIndex[o] ?? []
        case (nil, nil, nil):
            return triples
        }

        return candidates.compactMap { idx in
            let t = triples[idx]
            if let s = subject, t.subject != s { return nil }
            if let p = predicate, t.predicate != p { return nil }
            if let o = object, t.object != o { return nil }
            return t
        }
    }

    /// 全トリプル数
    var count: Int { triples.count }

    // MARK: - Private

    private static func spKey(_ s: String, _ p: String) -> String {
        "\(s)\0\(p)"
    }
}
