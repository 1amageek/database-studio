import SwiftUI
import Charts

/// 集約結果をチャートで表示するパネル
struct ChartPanelView: View {
    let panel: AnalyticsPanel
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ヘッダー
            HStack {
                Image(systemName: panel.chartType.systemImage)
                    .foregroundStyle(.secondary)
                Text(panel.query.label.isEmpty ? panel.query.function.rawValue : panel.query.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // チャートコンテンツ
            chartContent
                .frame(minHeight: 120)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    // MARK: - チャートコンテンツ

    @ViewBuilder
    private var chartContent: some View {
        if panel.results.isEmpty {
            ContentUnavailableView(
                "No Data",
                systemImage: "chart.bar",
                description: Text("No results for this query")
            )
            .frame(maxHeight: 100)
        } else {
            switch panel.chartType {
            case .kpi:
                kpiView
            case .bar:
                barChart
            case .line:
                lineChart
            case .pie:
                pieChart
            }
        }
    }

    // MARK: - KPI カード

    private var kpiView: some View {
        VStack(spacing: 4) {
            if let first = panel.results.first {
                Text(formattedValue(first.value))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if panel.results.count > 1 {
                    Text("\(panel.results.count) groups")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    // MARK: - 棒グラフ

    private var barChart: some View {
        Chart(panel.results) { result in
            BarMark(
                x: .value("Group", result.groupKey),
                y: .value("Value", result.value)
            )
            .foregroundStyle(by: .value("Group", result.groupKey))
        }
        .chartLegend(.hidden)
    }

    // MARK: - 折れ線グラフ

    private var lineChart: some View {
        Chart(panel.results) { result in
            LineMark(
                x: .value("Group", result.groupKey),
                y: .value("Value", result.value)
            )
            .symbol(Circle())
            PointMark(
                x: .value("Group", result.groupKey),
                y: .value("Value", result.value)
            )
        }
    }

    // MARK: - 円グラフ

    private var pieChart: some View {
        Chart(panel.results) { result in
            SectorMark(
                angle: .value("Value", result.value),
                innerRadius: .ratio(0.5),
                angularInset: 1
            )
            .foregroundStyle(by: .value("Group", result.groupKey))
        }
    }

    // MARK: - フォーマット

    private func formattedValue(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1_000_000 {
            return String(format: "%.0f", value)
        } else if abs(value) >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if abs(value) >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.2f", value)
        }
    }
}
