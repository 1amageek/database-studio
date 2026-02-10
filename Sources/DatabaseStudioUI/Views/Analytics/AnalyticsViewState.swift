import SwiftUI

/// Analytics ダッシュボードの状態管理
@Observable @MainActor
final class AnalyticsViewState {

    // MARK: - データ

    var document: AnalyticsDocument

    // MARK: - パネル

    var panels: [AnalyticsPanel] = []

    // MARK: - クエリエディタ

    var editingQuery: AggregationQuery = AggregationQuery()
    var editingChartType: ChartType = .bar
    var selectedPanelID: UUID?

    // MARK: - 初期化

    init(document: AnalyticsDocument) {
        self.document = document

        // デフォルトパネルを生成: Count
        let countQuery = AggregationQuery(function: .count, label: "Total Count")
        let countResults = AggregationEngine.execute(query: countQuery, items: document.items)
        panels.append(AnalyticsPanel(
            query: countQuery,
            chartType: .kpi,
            results: countResults
        ))

        // 最初の数値フィールドがあれば Sum パネルも追加
        if let firstNumeric = document.numericFieldNames.first {
            let sumQuery = AggregationQuery(
                function: .sum,
                fieldName: firstNumeric,
                label: "Sum of \(firstNumeric)"
            )
            let sumResults = AggregationEngine.execute(query: sumQuery, items: document.items)
            panels.append(AnalyticsPanel(
                query: sumQuery,
                chartType: .kpi,
                results: sumResults
            ))
        }

        // カテゴリカルフィールドを検出して GroupBy パネルを自動生成
        let categoricalFields = document.fieldNames.filter { name in
            !document.numericFieldNames.contains(name) && name != "id" && name != "_id"
        }

        // Count by 最初のカテゴリカルフィールド（Bar Chart）
        if let groupField = categoricalFields.first {
            let barQuery = AggregationQuery(
                function: .count,
                groupByField: groupField,
                label: "Count by \(groupField)"
            )
            let barResults = AggregationEngine.execute(query: barQuery, items: document.items)
            panels.append(AnalyticsPanel(
                query: barQuery,
                chartType: .bar,
                results: barResults
            ))
        }

        // Sum by 2番目のカテゴリカルフィールド（Pie Chart）
        if let firstNumeric = document.numericFieldNames.first,
           categoricalFields.count >= 2 {
            let pieQuery = AggregationQuery(
                function: .sum,
                fieldName: firstNumeric,
                groupByField: categoricalFields[1],
                label: "\(firstNumeric) by \(categoricalFields[1])"
            )
            let pieResults = AggregationEngine.execute(query: pieQuery, items: document.items)
            panels.append(AnalyticsPanel(
                query: pieQuery,
                chartType: .pie,
                results: pieResults
            ))
        }
    }

    // MARK: - ドキュメント更新

    func updateDocument(_ newDocument: AnalyticsDocument) {
        document = newDocument
        recalculateAllPanels()
    }

    // MARK: - パネル管理

    func addPanel() {
        let query = editingQuery
        let results = AggregationEngine.execute(query: query, items: document.items)

        // チャートタイプの自動判定
        let chartType: ChartType
        if query.groupByField == nil || query.groupByField?.isEmpty == true {
            chartType = .kpi
        } else {
            chartType = editingChartType
        }

        let panel = AnalyticsPanel(
            query: query,
            chartType: chartType,
            results: results
        )
        panels.append(panel)

        // エディタをリセット
        editingQuery = AggregationQuery()
    }

    func removePanel(id: UUID) {
        panels.removeAll { $0.id == id }
    }

    func recalculateAllPanels() {
        for i in panels.indices {
            panels[i].results = AggregationEngine.execute(
                query: panels[i].query,
                items: document.items
            )
        }
    }
}
