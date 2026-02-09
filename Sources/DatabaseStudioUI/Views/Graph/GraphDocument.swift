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

/// グラフノードの種別
public enum GraphNodeKind: String, Hashable, Sendable {
    case owlClass
    case individual
    case objectProperty
    case dataProperty
    case literal

    public var displayName: String {
        switch self {
        case .owlClass: return "Classes"
        case .individual: return "Individuals"
        case .objectProperty: return "Object Properties"
        case .dataProperty: return "Data Properties"
        case .literal: return "Literals"
        }
    }
}

/// グラフ内の単一ノード
public struct GraphNode: Identifiable, Hashable, Sendable {
    public let id: String
    public var label: String
    public var kind: GraphNodeKind
    public var metadata: [String: String]
    public var metrics: [String: Double]
    public var communityID: Int?
    public var isHighlighted: Bool

    public init(
        id: String,
        label: String,
        kind: GraphNodeKind,
        metadata: [String: String] = [:],
        metrics: [String: Double] = [:],
        communityID: Int? = nil,
        isHighlighted: Bool = false
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.metadata = metadata
        self.metrics = metrics
        self.communityID = communityID
        self.isHighlighted = isHighlighted
    }
}

/// グラフ内の単一エッジ
public struct GraphEdge: Identifiable, Hashable, Sendable {
    public let id: String
    public var sourceID: String
    public var targetID: String
    public var label: String
    public var weight: Double?
    public var isHighlighted: Bool

    public init(
        id: String,
        sourceID: String,
        targetID: String,
        label: String,
        weight: Double? = nil,
        isHighlighted: Bool = false
    ) {
        self.id = id
        self.sourceID = sourceID
        self.targetID = targetID
        self.label = label
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
