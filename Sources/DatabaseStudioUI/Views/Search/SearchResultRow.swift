import SwiftUI

/// Presents one ranked search result and its highlighted snippets.
struct SearchResultRow: View {
    let result: SearchResult
    let queryTokens: [String]
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                // Score badge.
                Text(String(format: "%.2f", result.score))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    // Record identifier.
                    Text(result.item.id)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)

                    // Highlighted snippets.
                    ForEach(Array(result.item.textFields.prefix(2)), id: \.key) { fieldName, text in
                        HStack(alignment: .top, spacing: 4) {
                            Text(fieldName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 50, alignment: .trailing)
                            highlightedText(text)
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

    // MARK: - Highlighting

    private func highlightedText(_ text: String) -> Text {
        guard !queryTokens.isEmpty else { return Text(text) }

        // Find every matching range.
        var matchedRanges: [Range<String.Index>] = []
        for token in queryTokens {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(
                    of: token,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<text.endIndex
                  ) {
                matchedRanges.append(range)
                searchStart = range.upperBound
            }
        }

        // Merge overlapping ranges.
        let orderedRanges = matchedRanges.sorted { $0.lowerBound < $1.lowerBound }
        var mergedRanges: [Range<String.Index>] = []
        for range in orderedRanges {
            if let previousRange = mergedRanges.last,
               previousRange.upperBound >= range.lowerBound {
                let mergedUpperBound = Swift.max(previousRange.upperBound, range.upperBound)
                mergedRanges[mergedRanges.count - 1] = previousRange.lowerBound..<mergedUpperBound
            } else {
                mergedRanges.append(range)
            }
        }

        guard !mergedRanges.isEmpty else { return Text(text) }

        var attributedText = AttributedString(text)
        for range in mergedRanges {
            guard let lowerBound = AttributedString.Index(range.lowerBound, within: attributedText),
                  let upperBound = AttributedString.Index(range.upperBound, within: attributedText) else {
                continue
            }
            attributedText[lowerBound..<upperBound].inlinePresentationIntent = .stronglyEmphasized
            attributedText[lowerBound..<upperBound].foregroundColor = .primary
        }

        return Text(attributedText)
    }
}
