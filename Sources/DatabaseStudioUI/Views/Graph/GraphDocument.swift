import Foundation

/// RDF トリプルの軽量表現。FDB に依存しない。
public struct RDFTripleData: Hashable, Sendable {
    public var subject: String
    public var predicate: String
    public var object: String

    public init(subject: String, predicate: String, object: String) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
    }
}

/// グラフ内でのノードの構造的役割
public enum GraphNodeRole: String, Hashable, Sendable, CaseIterable {
    case type       // クラス定義・テーブル定義（ex:Employee, Employee.self）
    case instance   // インスタンス（alice, bob）
    case property   // プロパティ定義（ex:worksFor）
    case literal    // リテラル値（"2024-01-01"）

    public var displayName: String {
        switch self {
        case .type:     return "Types"
        case .instance: return "Instances"
        case .property: return "Properties"
        case .literal:  return "Literals"
        }
    }
}

/// ノードの出自（どのデータソースから来たか）
public enum GraphNodeSource: String, Hashable, Sendable {
    case ontology    // OWLOntology のクラス・プロパティ定義
    case graphIndex  // GraphIndex（RDF トリプル）のデータ
    case persistable // Persistable 型のテーブルデータ
    case derived     // 推論・計算で生成
}

/// エッジの種類
public enum GraphEdgeKind: String, Hashable, Sendable {
    case subClassOf    // クラス階層（型 → 親型）
    case instanceOf    // インスタンスの型（alice → Employee）
    case relationship  // ドメイン関係（alice → dept1 via worksFor）
    case property      // プロパティ定義の接続（domain/range）
}

/// グラフ内の単一ノード
public struct GraphNode: Identifiable, Hashable, Sendable {
    public let id: String
    public var label: String
    public var role: GraphNodeRole
    public var ontologyClass: String?
    public var source: GraphNodeSource
    public var metadata: [String: String]
    public var metrics: [String: Double]
    public var isHighlighted: Bool

    public init(
        id: String,
        label: String,
        role: GraphNodeRole,
        ontologyClass: String? = nil,
        source: GraphNodeSource = .graphIndex,
        metadata: [String: String] = [:],
        metrics: [String: Double] = [:],
        isHighlighted: Bool = false
    ) {
        self.id = id
        self.label = label
        self.role = role
        self.ontologyClass = ontologyClass
        self.source = source
        self.metadata = metadata
        self.metrics = metrics
        self.isHighlighted = isHighlighted
    }
}

/// グラフ内の単一エッジ
public struct GraphEdge: Identifiable, Hashable, Sendable {
    public let id: String
    public var sourceID: String
    public var targetID: String
    public var label: String
    public var ontologyProperty: String?
    public var edgeKind: GraphEdgeKind
    public var weight: Double?
    public var isHighlighted: Bool

    public init(
        id: String,
        sourceID: String,
        targetID: String,
        label: String,
        ontologyProperty: String? = nil,
        edgeKind: GraphEdgeKind = .relationship,
        weight: Double? = nil,
        isHighlighted: Bool = false
    ) {
        self.id = id
        self.sourceID = sourceID
        self.targetID = targetID
        self.label = label
        self.ontologyProperty = ontologyProperty
        self.edgeKind = edgeKind
        self.weight = weight
        self.isHighlighted = isHighlighted
    }
}

/// ノードとエッジで構成されるグラフドキュメント
public struct GraphDocument: Sendable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]

    public init(nodes: [GraphNode] = [], edges: [GraphEdge] = []) {
        self.nodes = nodes
        self.edges = edges
    }

    /// owl:Thing ノードとその接続エッジを除外したドキュメントを返す
    /// owl:Thing は全クラスの暗黙的スーパークラスであり、表示すると全ノードと接続してしまう
    func removingOwlThing() -> GraphDocument {
        let thingIDs = Set(
            nodes.filter { isOwlThing($0.id, label: $0.label) }.map(\.id)
        )
        guard !thingIDs.isEmpty else { return self }
        return GraphDocument(
            nodes: nodes.filter { !thingIDs.contains($0.id) },
            edges: edges.filter { !thingIDs.contains($0.sourceID) && !thingIDs.contains($0.targetID) }
        )
    }
}

/// owl:Thing 判定（IRI 末尾またはラベルで判定）
private func isOwlThing(_ id: String, label: String) -> Bool {
    label == "Thing"
        || id.hasSuffix("#Thing")
        || id.hasSuffix("/Thing")
        || id == "owl:Thing"
}

/// IRI からローカル名を抽出する
/// - `http://example.org/onto#Person` → `Person`
/// - `ex:Person` → `Person`
func localName(_ iri: String) -> String {
    if let idx = iri.lastIndex(of: "#") {
        return String(iri[iri.index(after: idx)...])
    }
    if let idx = iri.lastIndex(of: "/") {
        return String(iri[iri.index(after: idx)...])
    }
    if let idx = iri.lastIndex(of: ":") {
        return String(iri[iri.index(after: idx)...])
    }
    return iri
}
