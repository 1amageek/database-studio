import Foundation

// MARK: - Filter Mode

/// フィルターの適用モード
enum GraphFilterMode: String, Hashable, CaseIterable, Sendable {
    case include  // 合致するものだけ表示
    case exclude  // 合致するものを非表示

    var label: String {
        switch self {
        case .include: "Include"
        case .exclude: "Exclude"
        }
    }

    var systemImage: String {
        switch self {
        case .include: "plus.circle.fill"
        case .exclude: "minus.circle.fill"
        }
    }
}

// MARK: - Comparison Operator

/// メトリクス閾値の比較演算子
enum GraphFilterComparisonOp: String, CaseIterable, Hashable, Sendable {
    case greaterThan = ">"
    case lessThan = "<"
    case greaterOrEqual = ">="
    case lessOrEqual = "<="

    func evaluate(_ lhs: Double, _ rhs: Double) -> Bool {
        switch self {
        case .greaterThan: lhs > rhs
        case .lessThan: lhs < rhs
        case .greaterOrEqual: lhs >= rhs
        case .lessOrEqual: lhs <= rhs
        }
    }
}

// MARK: - Filter Facet

/// 単一のファセットフィルター
///
/// ファセット内の複数値は OR（いずれかに合致すれば OK）。
/// ファセット間は AND（すべてのファセットに合致する必要がある）。
enum GraphFilterFacet: Hashable, Sendable {

    case nodeRole(Set<GraphNodeRole>)
    case nodeType(Set<String>)
    case nodeSource(Set<GraphNodeSource>)
    case edgeKind(Set<GraphEdgeKind>)
    case edgeLabel(Set<String>)
    case metricThreshold(metric: String, op: GraphFilterComparisonOp, value: Double)
    case metadataContains(key: String?, value: String)

    // MARK: - Node Matching

    /// ノードがこのファセットに合致するか
    func matchesNode(_ node: GraphNode, nodeTypeMap: [String: Set<String>]) -> Bool {
        switch self {
        case .nodeRole(let roles):
            return roles.contains(node.role)

        case .nodeType(let typeIDs):
            // ontologyClass が直接合致
            if let cls = node.ontologyClass, typeIDs.contains(cls) {
                return true
            }
            // nodeTypeMap 経由で rdf:type 関係を確認
            if let types = nodeTypeMap[node.id] {
                return !types.isDisjoint(with: typeIDs)
            }
            // type ノード自身が typeIDs に含まれる
            return typeIDs.contains(node.id)

        case .nodeSource(let sources):
            return sources.contains(node.source)

        case .metricThreshold(let metric, let op, let threshold):
            guard let value = node.metrics[metric] else { return false }
            return op.evaluate(value, threshold)

        case .metadataContains(let key, let value):
            let query = value.lowercased()
            if let key {
                return node.metadata[key]?.lowercased().contains(query) == true
            }
            return node.metadata.values.contains { $0.lowercased().contains(query) }

        case .edgeKind, .edgeLabel:
            // エッジファセットはノード判定に関与しない
            return true
        }
    }

    // MARK: - Edge Matching

    /// エッジがこのファセットに合致するか
    func matchesEdge(_ edge: GraphEdge) -> Bool {
        switch self {
        case .edgeKind(let kinds):
            return kinds.contains(edge.edgeKind)

        case .edgeLabel(let labels):
            return labels.contains(edge.label)

        case .nodeRole, .nodeType, .nodeSource, .metricThreshold, .metadataContains:
            // ノードファセットはエッジ判定に関与しない
            return true
        }
    }

    // MARK: - Facet Classification

    /// このファセットがノード属性を対象とするか
    var isNodeFacet: Bool {
        switch self {
        case .nodeRole, .nodeType, .nodeSource, .metricThreshold, .metadataContains:
            return true
        case .edgeKind, .edgeLabel:
            return false
        }
    }

    /// このファセットがエッジ属性を対象とするか
    var isEdgeFacet: Bool {
        switch self {
        case .edgeKind, .edgeLabel:
            return true
        case .nodeRole, .nodeType, .nodeSource, .metricThreshold, .metadataContains:
            return false
        }
    }

    // MARK: - UI Labels

    /// ファセットのカテゴリ名
    var categoryLabel: String {
        switch self {
        case .nodeRole: "Role"
        case .nodeType: "Type"
        case .nodeSource: "Source"
        case .edgeKind: "Edge Kind"
        case .edgeLabel: "Edge Label"
        case .metricThreshold: "Metric"
        case .metadataContains: "Metadata"
        }
    }

    /// チップに表示する値のサマリー
    var valueSummary: String {
        switch self {
        case .nodeRole(let roles):
            return roles.map(\.displayName).sorted().joined(separator: ", ")

        case .nodeType(let typeIDs):
            let labels = typeIDs.map { localName($0) }.sorted()
            if labels.count <= 2 {
                return labels.joined(separator: ", ")
            }
            return "\(labels[0]), \(labels[1]) +\(labels.count - 2)"

        case .nodeSource(let sources):
            return sources.map(\.rawValue).sorted().joined(separator: ", ")

        case .edgeKind(let kinds):
            return kinds.map(\.rawValue).sorted().joined(separator: ", ")

        case .edgeLabel(let labels):
            let sorted = labels.sorted()
            if sorted.count <= 2 {
                return sorted.joined(separator: ", ")
            }
            return "\(sorted[0]), \(sorted[1]) +\(sorted.count - 2)"

        case .metricThreshold(let metric, let op, let value):
            return "\(metric) \(op.rawValue) \(String(format: "%.4f", value))"

        case .metadataContains(let key, let value):
            if let key {
                return "\(key): \(value)"
            }
            return value
        }
    }
}

// MARK: - Filter Token

/// モード付きファセットフィルター
struct GraphFilterToken: Identifiable, Hashable, Sendable {
    let id: UUID
    var mode: GraphFilterMode
    var facet: GraphFilterFacet

    init(id: UUID = UUID(), mode: GraphFilterMode = .include, facet: GraphFilterFacet) {
        self.id = id
        self.mode = mode
        self.facet = facet
    }
}

// MARK: - Filter Preset

/// よく使うフィルターパターン
enum GraphFilterPreset: CaseIterable, Sendable {
    case typesOnly
    case instancesOnly
    case hideLiterals
    case ontologyOnly
    case graphIndexOnly

    var label: String {
        switch self {
        case .typesOnly: "Types Only"
        case .instancesOnly: "Instances Only"
        case .hideLiterals: "Hide Literals"
        case .ontologyOnly: "Ontology Only"
        case .graphIndexOnly: "Graph Data Only"
        }
    }

    var systemImage: String {
        switch self {
        case .typesOnly: "rectangle.3.group"
        case .instancesOnly: "person.3"
        case .hideLiterals: "text.badge.minus"
        case .ontologyOnly: "building.columns"
        case .graphIndexOnly: "cylinder"
        }
    }

    var token: GraphFilterToken {
        switch self {
        case .typesOnly:
            GraphFilterToken(mode: .include, facet: .nodeRole([.type]))
        case .instancesOnly:
            GraphFilterToken(mode: .include, facet: .nodeRole([.instance]))
        case .hideLiterals:
            GraphFilterToken(mode: .exclude, facet: .nodeRole([.literal]))
        case .ontologyOnly:
            GraphFilterToken(mode: .include, facet: .nodeSource([.ontology]))
        case .graphIndexOnly:
            GraphFilterToken(mode: .include, facet: .nodeSource([.graphIndex]))
        }
    }
}

// MARK: - Facet Category (for Add Filter menu)

/// フィルター追加メニュー用のファセットカテゴリ
enum GraphFilterFacetCategory: CaseIterable, Sendable {
    case nodeRole
    case nodeType
    case nodeSource
    case edgeKind
    case edgeLabel
    case metricThreshold
    case metadataContains

    var label: String {
        switch self {
        case .nodeRole: "Node Role"
        case .nodeType: "Node Type"
        case .nodeSource: "Node Source"
        case .edgeKind: "Edge Kind"
        case .edgeLabel: "Edge Label"
        case .metricThreshold: "Metric Threshold"
        case .metadataContains: "Metadata"
        }
    }

    var systemImage: String {
        switch self {
        case .nodeRole: "tag"
        case .nodeType: "rectangle.3.group"
        case .nodeSource: "tray.full"
        case .edgeKind: "arrow.triangle.branch"
        case .edgeLabel: "text.badge.star"
        case .metricThreshold: "chart.bar"
        case .metadataContains: "doc.text.magnifyingglass"
        }
    }

    /// デフォルト値で初期トークンを生成
    func makeDefaultToken() -> GraphFilterToken {
        switch self {
        case .nodeRole:
            GraphFilterToken(facet: .nodeRole(Set(GraphNodeRole.allCases)))
        case .nodeType:
            GraphFilterToken(facet: .nodeType([]))
        case .nodeSource:
            GraphFilterToken(facet: .nodeSource(Set(GraphNodeSource.allCases)))
        case .edgeKind:
            GraphFilterToken(facet: .edgeKind(Set(GraphEdgeKind.allCases)))
        case .edgeLabel:
            GraphFilterToken(facet: .edgeLabel([]))
        case .metricThreshold:
            GraphFilterToken(facet: .metricThreshold(metric: "degree", op: .greaterThan, value: 0.0))
        case .metadataContains:
            GraphFilterToken(facet: .metadataContains(key: nil, value: ""))
        }
    }
}

// MARK: - CaseIterable for GraphNodeSource / GraphEdgeKind

extension GraphNodeSource: CaseIterable {
    public static var allCases: [GraphNodeSource] {
        [.ontology, .graphIndex, .persistable, .derived]
    }
}

extension GraphEdgeKind: CaseIterable {
    public static var allCases: [GraphEdgeKind] {
        [.subClassOf, .instanceOf, .relationship, .property]
    }
}
