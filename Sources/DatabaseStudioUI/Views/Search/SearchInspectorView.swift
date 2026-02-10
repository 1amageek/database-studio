import SwiftUI

/// 検索結果詳細のインスペクター
struct SearchInspectorView: View {
    let result: SearchResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                scoreSection
                fieldScoresSection
                documentSection
            }
            .padding()
        }
    }

    // MARK: - スコア

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Score", systemImage: "gauge.with.dots.needle.33percent")
                .font(.subheadline.weight(.semibold))

            Text(String(format: "%.4f", result.score))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    // MARK: - フィールドスコア

    private var fieldScoresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BM25 Breakdown")
                .font(.subheadline.weight(.semibold))

            if result.fieldScores.isEmpty {
                Text("No field-level scores available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let sortedScores = result.fieldScores.sorted { $0.value > $1.value }
                let maxScore = sortedScores.first?.value ?? 1.0

                ForEach(sortedScores, id: \.key) { field, score in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(field)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.3f", score))
                                .font(.caption.monospacedDigit())
                        }

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.blue.opacity(0.3))
                                .frame(width: geo.size.width * CGFloat(score / maxScore))
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
    }

    // MARK: - ドキュメント

    private var documentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Document")
                .font(.subheadline.weight(.semibold))

            let sortedFields = result.item.allFields.sorted { $0.key < $1.key }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                ForEach(sortedFields, id: \.key) { key, value in
                    GridRow {
                        Text(key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 80, alignment: .trailing)
                        Text(value)
                            .font(.caption)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
