import Foundation

/// 集約関数
public enum AggregationFunction: String, CaseIterable, Identifiable, Sendable {
    case count = "Count"
    case sum = "Sum"
    case avg = "Average"
    case min = "Min"
    case max = "Max"
    case percentile = "Percentile"

    public var id: String { rawValue }

    /// count はフィールド不要
    public var requiresField: Bool {
        self != .count
    }
}

/// 集約クエリ
public struct AggregationQuery: Identifiable, Sendable {
    public let id: UUID
    public var function: AggregationFunction
    public var fieldName: String?
    public var groupByField: String?
    public var percentileValue: Double
    public var label: String

    public init(
        id: UUID = UUID(),
        function: AggregationFunction = .count,
        fieldName: String? = nil,
        groupByField: String? = nil,
        percentileValue: Double = 0.95,
        label: String = ""
    ) {
        self.id = id
        self.function = function
        self.fieldName = fieldName
        self.groupByField = groupByField
        self.percentileValue = percentileValue
        self.label = label.isEmpty ? function.rawValue : label
    }
}

/// 集約結果
public struct AggregationResult: Identifiable, Sendable {
    public let id: UUID
    public let groupKey: String
    public let value: Double
    public let label: String

    public init(
        id: UUID = UUID(),
        groupKey: String = "",
        value: Double,
        label: String = ""
    ) {
        self.id = id
        self.groupKey = groupKey
        self.value = value
        self.label = label
    }
}

/// チャート種別
public enum ChartType: String, CaseIterable, Identifiable, Sendable {
    case bar = "Bar"
    case line = "Line"
    case pie = "Pie"
    case kpi = "KPI"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .bar: return "chart.bar"
        case .line: return "chart.line.uptrend.xyaxis"
        case .pie: return "chart.pie"
        case .kpi: return "number"
        }
    }
}

/// ダッシュボードパネル
public struct AnalyticsPanel: Identifiable, Sendable {
    public let id: UUID
    public var query: AggregationQuery
    public var chartType: ChartType
    public var results: [AggregationResult]

    public init(
        id: UUID = UUID(),
        query: AggregationQuery,
        chartType: ChartType = .bar,
        results: [AggregationResult] = []
    ) {
        self.id = id
        self.query = query
        self.chartType = chartType
        self.results = results
    }
}

/// Analytics ドキュメント
public struct AnalyticsDocument: @unchecked Sendable {
    public var items: [[String: Any]]
    public var entityName: String
    public var fieldNames: [String]
    public var numericFieldNames: [String]

    public init(
        items: [[String: Any]] = [],
        entityName: String = "",
        fieldNames: [String] = [],
        numericFieldNames: [String] = []
    ) {
        self.items = items
        self.entityName = entityName
        self.fieldNames = fieldNames
        self.numericFieldNames = numericFieldNames
    }

    public init(items: [[String: Any]], entityName: String) {
        self.items = items
        self.entityName = entityName

        // フィールド名を自動検出
        var allFields: Set<String> = []
        var numericFields: Set<String> = []
        for item in items {
            for (key, value) in item {
                allFields.insert(key)
                if Self.isNumeric(value) {
                    numericFields.insert(key)
                }
            }
        }
        self.fieldNames = allFields.sorted()
        self.numericFieldNames = numericFields.sorted()
    }

    private static func isNumeric(_ value: Any) -> Bool {
        value is Int || value is Int64 || value is Double || value is Float ||
        value is UInt || value is UInt64
    }
}
