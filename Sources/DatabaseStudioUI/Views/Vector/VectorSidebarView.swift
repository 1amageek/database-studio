import SwiftUI

/// Vector Explorer サイドバー
struct VectorSidebarView: View {
    @Bindable var state: VectorViewState

    var body: some View {
        List {
            infoSection
            mappingSection
            knnSection
            if !state.nearestNeighbors.isEmpty {
                nearestNeighborsSection
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - 情報

    private var infoSection: some View {
        Section("Dataset") {
            LabeledContent("Points", value: "\(state.document.points.count)")
                .font(.caption)
            LabeledContent("Dimensions", value: "\(state.document.dimensions)")
                .font(.caption)
        }
    }

    // MARK: - ビジュアルマッピング

    private var mappingSection: some View {
        Section("Visual Mapping") {
            Picker("Color By", selection: Binding(
                get: { state.colorByField ?? "" },
                set: { state.colorByField = $0.isEmpty ? nil : $0 }
            )) {
                Text("Uniform").tag("")
                ForEach(state.document.fieldNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .font(.caption)

            Picker("Size By", selection: Binding(
                get: { state.sizeByField ?? "" },
                set: { state.sizeByField = $0.isEmpty ? nil : $0 }
            )) {
                Text("Uniform").tag("")
                ForEach(state.document.fieldNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .font(.caption)

            Toggle("Labels", isOn: $state.showLabels)
                .font(.caption)
        }
    }

    // MARK: - KNN パラメータ

    private var knnSection: some View {
        Section("KNN Search") {
            Stepper("Neighbors: \(state.neighborLimit)", value: $state.neighborLimit, in: 1...50)
                .font(.caption)

            Picker("Metric", selection: $state.comparisonMetric) {
                ForEach(VectorComparisonMetric.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .font(.caption)

            if state.selectedPoint == nil {
                Text("Select a point to find neighbors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - KNN 結果

    private var nearestNeighborsSection: some View {
        Section("Nearest Neighbors (\(state.nearestNeighbors.count))") {
            ForEach(Array(state.nearestNeighbors.enumerated()), id: \.element.id) { index, result in
                Button {
                    state.selectedPointID = result.id
                } label: {
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        Text(result.point.label)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text(result.formattedScore)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
