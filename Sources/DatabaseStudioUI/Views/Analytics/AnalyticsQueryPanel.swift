import SwiftUI

/// 集約クエリ構築パネル
struct AnalyticsQueryPanel: View {
    @Bindable var state: AnalyticsViewState

    var body: some View {
        List {
            queryBuilderSection
            chartTypeSection
        }
        .listStyle(.sidebar)
    }

    // MARK: - クエリビルダー

    private var queryBuilderSection: some View {
        Section("Query") {
            // 集約関数
            Picker("Function", selection: $state.editingQuery.function) {
                ForEach(AggregationFunction.allCases) { fn in
                    Text(fn.rawValue).tag(fn)
                }
            }

            // フィールド（count 以外）
            if state.editingQuery.function.requiresField {
                Picker("Field", selection: Binding(
                    get: { state.editingQuery.fieldName ?? "" },
                    set: { state.editingQuery.fieldName = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Select...").tag("")
                    ForEach(state.document.numericFieldNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }

            // パーセンタイル値
            if state.editingQuery.function == .percentile {
                HStack {
                    Text("Percentile")
                    Spacer()
                    TextField(
                        "0.95",
                        value: $state.editingQuery.percentileValue,
                        format: .number.precision(.fractionLength(2))
                    )
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                }
            }

            // Group By
            Picker("Group By", selection: Binding(
                get: { state.editingQuery.groupByField ?? "" },
                set: { state.editingQuery.groupByField = $0.isEmpty ? nil : $0 }
            )) {
                Text("None").tag("")
                ForEach(state.document.fieldNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }

            // ラベル
            TextField("Label", text: $state.editingQuery.label)

            // 実行ボタン
            Button {
                state.addPanel()
            } label: {
                Label("Add Panel", systemImage: "plus.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - チャート種別

    private var chartTypeSection: some View {
        Section("Chart Type") {
            ForEach(ChartType.allCases) { type in
                chartTypeButton(type)
            }
        }
    }

    private func chartTypeButton(_ type: ChartType) -> some View {
        let isActive = state.editingChartType == type
        return Button {
            state.editingChartType = type
        } label: {
            Label(type.rawValue, systemImage: type.systemImage)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .fontWeight(isActive ? .semibold : .regular)
    }
}
