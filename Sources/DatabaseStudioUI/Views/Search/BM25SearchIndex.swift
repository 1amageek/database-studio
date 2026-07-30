import Foundation

/// An in-memory search index ranked with BM25.
///
/// Reference: Robertson, S.E. and Zaragoza, H., "The Probabilistic Relevance Framework:
/// BM25 and Beyond", Foundations and Trends in Information Retrieval, 2009
@MainActor
final class BM25SearchIndex {

    // MARK: - Ranking Parameters

    let termFrequencySaturation: Double = 1.2
    let lengthNormalization: Double = 0.75

    // MARK: - Search Index

    /// Maps a field-qualified term to item positions and term frequencies.
    private var postingsByTerm: [String: [(itemIndex: Int, termFrequency: Int)]] = [:]

    /// Maps a field-qualified term to the items containing it.
    private var itemIndicesByTerm: [String: Set<Int>] = [:]

    /// Stores token counts by item position and field.
    private var fieldLengthsByItem: [Int: [String: Int]] = [:]

    /// Stores the average token count for each indexed field.
    private var averageFieldLengths: [String: Double] = [:]

    private var indexedItemCount: Int = 0

    private var indexedItems: [SearchableItem] = []

    // MARK: - Indexing

    func replaceItems(with items: [SearchableItem]) {
        indexedItems = items
        indexedItemCount = items.count
        postingsByTerm = [:]
        itemIndicesByTerm = [:]
        fieldLengthsByItem = [:]
        averageFieldLengths = [:]

        var fieldLengthSums: [String: Int] = [:]

        for (itemIndex, item) in items.enumerated() {
            var itemFieldLengths: [String: Int] = [:]

            for (fieldName, text) in item.textFields {
                let tokens = tokenize(text)
                itemFieldLengths[fieldName] = tokens.count
                fieldLengthSums[fieldName, default: 0] += tokens.count

                var termFrequencies: [String: Int] = [:]
                for token in tokens {
                    termFrequencies[token, default: 0] += 1
                }

                for (term, termFrequency) in termFrequencies {
                    let qualifiedTerm = "\(fieldName):\(term)"
                    postingsByTerm[qualifiedTerm, default: []].append(
                        (itemIndex: itemIndex, termFrequency: termFrequency)
                    )
                    itemIndicesByTerm[qualifiedTerm, default: []].insert(itemIndex)
                }
            }

            fieldLengthsByItem[itemIndex] = itemFieldLengths
        }

        for (fieldName, totalLength) in fieldLengthSums {
            averageFieldLengths[fieldName] = indexedItemCount > 0
                ? Double(totalLength) / Double(indexedItemCount)
                : 0
        }
    }

    // MARK: - Search

    func search(
        query: String,
        mode: SearchMatchMode,
        limit: Int = 100
    ) -> [SearchResult] {
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return [] }

        var itemScores: [Int: Double] = [:]
        var itemFieldScores: [Int: [String: Double]] = [:]

        let fieldNames = Set(indexedItems.flatMap { $0.textFields.keys })

        for fieldName in fieldNames {
            let averageFieldLength = averageFieldLengths[fieldName] ?? 1.0

            for token in queryTokens {
                let qualifiedTerm = "\(fieldName):\(token)"
                guard let postings = postingsByTerm[qualifiedTerm] else { continue }

                let documentFrequency = Double(postings.count)
                let documentCount = Double(indexedItemCount)
                let inverseDocumentFrequency = log(
                    (documentCount - documentFrequency + 0.5) / (documentFrequency + 0.5) + 1.0
                )

                for posting in postings {
                    let termFrequency = Double(posting.termFrequency)
                    let fieldLength = Double(fieldLengthsByItem[posting.itemIndex]?[fieldName] ?? 0)
                    let normalizedLength = 1 - lengthNormalization
                        + lengthNormalization * fieldLength / averageFieldLength
                    let score = inverseDocumentFrequency
                        * (termFrequency * (termFrequencySaturation + 1))
                        / (termFrequency + termFrequencySaturation * normalizedLength)

                    itemScores[posting.itemIndex, default: 0] += score
                    itemFieldScores[posting.itemIndex, default: [:]][fieldName, default: 0] += score
                }
            }
        }

        let matchingItemIndices: Set<Int>
        switch mode {
        case .all:
            matchingItemIndices = Set(itemScores.keys.filter { itemIndex in
                queryTokens.allSatisfy { token in
                    fieldNames.contains { fieldName in
                        let qualifiedTerm = "\(fieldName):\(token)"
                        return itemIndicesByTerm[qualifiedTerm]?.contains(itemIndex) == true
                    }
                }
            })

        case .any:
            matchingItemIndices = Set(itemScores.keys)

        case .phrase:
            let phrase = query.lowercased()
            matchingItemIndices = Set(indexedItems.indices.filter { itemIndex in
                indexedItems[itemIndex].textFields.values.contains { $0.lowercased().contains(phrase) }
            })
        }

        var results: [SearchResult] = []
        for itemIndex in matchingItemIndices {
            guard let score = itemScores[itemIndex], score > 0 else { continue }
            let item = indexedItems[itemIndex]

            var matchRanges: [String: [Range<String.Index>]] = [:]
            for (fieldName, text) in item.textFields {
                var ranges: [Range<String.Index>] = []
                for token in queryTokens {
                    var searchStart = text.startIndex
                    while searchStart < text.endIndex,
                          let range = text.range(
                            of: token,
                            options: [.caseInsensitive, .diacriticInsensitive],
                            range: searchStart..<text.endIndex
                          ) {
                        ranges.append(range)
                        searchStart = range.upperBound
                    }
                }
                if !ranges.isEmpty {
                    matchRanges[fieldName] = ranges
                }
            }

            results.append(SearchResult(
                item: item,
                score: score,
                fieldScores: itemFieldScores[itemIndex] ?? [:],
                matchRanges: matchRanges
            ))
        }

        results.sort { $0.score > $1.score }
        return Array(results.prefix(limit))
    }

    // MARK: - Facets

    func facets(
        results: [SearchResult],
        fieldNames: [String],
        allItems: [SearchableItem]
    ) -> [Facet] {
        var facets: [Facet] = []

        for fieldName in fieldNames {
            var counts: [String: Int] = [:]

            for result in results {
                if let value = result.item.allFields[fieldName], !value.isEmpty {
                    counts[value, default: 0] += 1
                }
            }

            let uniqueRatio = Double(counts.count) / Double(max(allItems.count, 1))
            guard uniqueRatio < 0.5, counts.count > 1, counts.count <= 50 else { continue }

            let values = counts
                .sorted { $0.value > $1.value }
                .map { FacetValue(value: $0.key, count: $0.value) }

            facets.append(Facet(fieldName: fieldName, values: values))
        }

        return facets
    }

    // MARK: - Tokenization

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count >= 2 }
    }
}
