import SwiftUI

/// 選択ベクトルポイントの詳細インスペクター
struct VectorInspectorView: View {
    let point: VectorPoint
    let knnResults: [VectorSearchResult]
    let metric: VectorMetric

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pointInfoSection
                embeddingSection
                fieldsSection
                if !knnResults.isEmpty {
                    knnSection
                }
            }
            .padding()
        }
    }

    // MARK: - ポイント情報

    private var pointInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(point.label, systemImage: "cube.transparent")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(point.id)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Dimensions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(point.embedding.count)")
                        .font(.caption.monospacedDigit())
                }
                GridRow {
                    Text("Projected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "(%.2f, %.2f)", point.projected.x, point.projected.y))
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    // MARK: - 埋め込みプレビュー

    private var embeddingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Embedding")
                .font(.subheadline.weight(.semibold))

            // 先頭8次元のプレビュー
            let preview = Array(point.embedding.prefix(8))
            HStack(spacing: 2) {
                ForEach(Array(preview.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(embeddingColor(value))
                        .frame(width: 20, height: 20)
                }
                if point.embedding.count > 8 {
                    Text("...\(point.embedding.count - 8) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // 統計
            let values = point.embedding
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 0
            let mean = values.reduce(0, +) / Float(max(values.count, 1))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow {
                    Text("Min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.4f", minVal))
                        .font(.caption2.monospacedDigit())
                }
                GridRow {
                    Text("Max")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.4f", maxVal))
                        .font(.caption2.monospacedDigit())
                }
                GridRow {
                    Text("Mean")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.4f", mean))
                        .font(.caption2.monospacedDigit())
                }
            }
        }
    }

    // MARK: - フィールド

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fields")
                .font(.subheadline.weight(.semibold))

            if point.fields.isEmpty {
                Text("No fields")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(point.fields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        GridRow {
                            Text(key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 80, alignment: .trailing)
                            Text(value)
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - KNN 結果

    private var knnSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(metric.rawValue) Neighbors")
                .font(.subheadline.weight(.semibold))

            ForEach(Array(knnResults.enumerated()), id: \.element.id) { index, result in
                HStack {
                    Text("\(index + 1).")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(result.point.label)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(result.formattedSimilarity)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - ヘルパー

    private func embeddingColor(_ value: Float) -> Color {
        if value > 0 {
            return .blue.opacity(Double(min(abs(value), 1.0)))
        } else {
            return .red.opacity(Double(min(abs(value), 1.0)))
        }
    }
}
