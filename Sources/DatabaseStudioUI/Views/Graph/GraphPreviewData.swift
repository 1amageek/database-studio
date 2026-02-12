import Foundation

// MARK: - Graph Preview 用サンプルデータ

enum GraphPreviewData {

    /// 自動車業界の RDF トリプル（企業・関連・属性）
    static let triples: [RDFTripleData] = [
        // 型定義
        RDFTripleData(subject: "ex:Toyota", predicate: "rdf:type", object: "ex:AutomotiveManufacturer"),
        RDFTripleData(subject: "ex:Daihatsu", predicate: "rdf:type", object: "ex:AutomotiveManufacturer"),
        RDFTripleData(subject: "ex:Denso", predicate: "rdf:type", object: "ex:Supplier"),
        RDFTripleData(subject: "ex:ToyotaCity", predicate: "rdf:type", object: "ex:City"),
        RDFTripleData(subject: "ex:Japan", predicate: "rdf:type", object: "ex:Country"),

        // 関係
        RDFTripleData(subject: "ex:Toyota", predicate: "ex:hasSubsidiary", object: "ex:Daihatsu"),
        RDFTripleData(subject: "ex:Toyota", predicate: "ex:hasSupplier", object: "ex:Denso"),
        RDFTripleData(subject: "ex:Toyota", predicate: "ex:headquarteredIn", object: "ex:ToyotaCity"),
        RDFTripleData(subject: "ex:ToyotaCity", predicate: "ex:locatedIn", object: "ex:Japan"),
        RDFTripleData(subject: "ex:Daihatsu", predicate: "ex:headquarteredIn", object: "ex:Japan"),
        RDFTripleData(subject: "ex:Denso", predicate: "ex:headquarteredIn", object: "ex:Japan"),

        // リテラル属性
        RDFTripleData(subject: "ex:Toyota", predicate: "ex:foundedYear", object: "\"1937\""),
        RDFTripleData(subject: "ex:Toyota", predicate: "ex:scale", object: "\"Global\""),
        RDFTripleData(subject: "ex:Daihatsu", predicate: "ex:foundedYear", object: "\"1951\""),
        RDFTripleData(subject: "ex:Denso", predicate: "ex:foundedYear", object: "\"1949\""),
    ]

    /// RDF トリプルから生成した GraphDocument
    static let rdfDocument: GraphDocument = GraphDocument(triples: triples)

    /// 手動構築のオントロジー風 GraphDocument（TBox 表現）
    static let ontologyDocument: GraphDocument = {
        let nodes: [GraphNode] = [
            GraphNode(id: "ex:Organization", label: "Organization", role: .type),
            GraphNode(id: "ex:Corporation", label: "Corporation", role: .type),
            GraphNode(id: "ex:Manufacturer", label: "Manufacturer", role: .type),
            GraphNode(id: "ex:AutomotiveManufacturer", label: "AutomotiveManufacturer", role: .type),
            GraphNode(id: "ex:Supplier", label: "Supplier", role: .type),
            GraphNode(id: "ex:GlobalManufacturer", label: "GlobalManufacturer", role: .type,
                      metadata: ["definedAs": "Corporation AND scale=Global"]),
            GraphNode(id: "ex:City", label: "City", role: .type),
            GraphNode(id: "ex:Country", label: "Country", role: .type),
            GraphNode(id: "ex:Location", label: "Location", role: .type),
        ]
        let edges: [GraphEdge] = [
            GraphEdge(id: "e1", sourceID: "ex:Corporation", targetID: "ex:Organization", label: "subClassOf"),
            GraphEdge(id: "e2", sourceID: "ex:Manufacturer", targetID: "ex:Corporation", label: "subClassOf"),
            GraphEdge(id: "e3", sourceID: "ex:AutomotiveManufacturer", targetID: "ex:Manufacturer", label: "subClassOf"),
            GraphEdge(id: "e4", sourceID: "ex:Supplier", targetID: "ex:Organization", label: "subClassOf"),
            GraphEdge(id: "e5", sourceID: "ex:GlobalManufacturer", targetID: "ex:Manufacturer", label: "equivalentTo"),
            GraphEdge(id: "e6", sourceID: "ex:City", targetID: "ex:Location", label: "subClassOf"),
            GraphEdge(id: "e7", sourceID: "ex:Country", targetID: "ex:Location", label: "subClassOf"),
            GraphEdge(id: "e8", sourceID: "ex:AutomotiveManufacturer", targetID: "ex:City", label: "headquarteredIn"),
        ]
        return GraphDocument(nodes: nodes, edges: edges)
    }()

    /// DetailPanel 用のサンプルノード
    static let sampleNode: GraphNode = GraphNode(
        id: "ex:Toyota",
        label: "Toyota",
        role: .instance,
        metadata: ["foundedYear": "1937", "scale": "Global"]
    )

    /// sampleNode の incoming エッジ
    static let sampleIncoming: [GraphEdge] = []

    /// sampleNode の outgoing エッジ
    static let sampleOutgoing: [GraphEdge] = [
        GraphEdge(id: "o1", sourceID: "ex:Toyota", targetID: "ex:Daihatsu", label: "hasSubsidiary"),
        GraphEdge(id: "o2", sourceID: "ex:Toyota", targetID: "ex:Denso", label: "hasSupplier"),
        GraphEdge(id: "o3", sourceID: "ex:Toyota", targetID: "ex:ToyotaCity", label: "headquarteredIn"),
    ]
}
