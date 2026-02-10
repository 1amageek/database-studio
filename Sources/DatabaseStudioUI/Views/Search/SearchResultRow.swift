import SwiftUI

/// 検索結果1行の表示
struct SearchResultRow: View {
    let result: SearchResult
    let queryTokens: [String]
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                // スコアバッジ
                Text(String(format: "%.2f", result.score))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    // ID
                    Text(result.item.id)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)

                    // スニペット（ハイライト付き）
                    ForEach(Array(result.item.textFields.prefix(2)), id: \.key) { fieldName, text in
                        HStack(alignment: .top, spacing: 4) {
                            Text(fieldName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 50, alignment: .trailing)
                            highlightedText(text: text, fieldName: fieldName)
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - ハイライト

    private func highlightedText(text: String, fieldName: String) -> Text {
        guard !queryTokens.isEmpty else { return Text(text) }

        let lowText = text.lowercased()
        var highlights: [(range: Range<String.Index>, matched: Bool)] = []

        // マッチ範囲を見つける
        var matchedRanges: [Range<String.Index>] = []
        for token in queryTokens {
            var searchStart = lowText.startIndex
            while searchStart < lowText.endIndex,
                  let range = lowText.range(of: token, range: searchStart..<lowText.endIndex) {
                matchedRanges.append(range)
                searchStart = range.upperBound
            }
        }

        // マッチ範囲をソートしてマージ
        let sorted = matchedRanges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in sorted {
            if let last = merged.last, last.upperBound >= range.lowerBound {
                let newEnd = Swift.max(last.upperBound, range.upperBound)
                merged[merged.count - 1] = last.lowerBound..<newEnd
            } else {
                merged.append(range)
            }
        }

        // テキストを構築
        if merged.isEmpty { return Text(text) }

        var result = Text("")
        var currentIndex = text.startIndex

        for range in merged {
            if currentIndex < range.lowerBound {
                result = result + Text(text[currentIndex..<range.lowerBound])
            }
            result = result + Text(text[range])
                .bold()
                .foregroundStyle(.primary)
            currentIndex = range.upperBound
        }

        if currentIndex < text.endIndex {
            result = result + Text(text[currentIndex..<text.endIndex])
        }

        return result
    }
}
