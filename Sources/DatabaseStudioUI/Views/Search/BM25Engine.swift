import Foundation

/// BM25 全文検索エンジン（メモリ内）
///
/// Reference: Robertson, S.E. and Zaragoza, H., "The Probabilistic Relevance Framework:
/// BM25 and Beyond", Foundations and Trends in Information Retrieval, 2009
final class BM25Engine: @unchecked Sendable {

    // MARK: - BM25 パラメータ

    let k1: Double = 1.2
    let b: Double = 0.75

    // MARK: - 転置インデックス

    /// term → [(docIndex, termFrequency)]
    private var invertedIndex: [String: [(docIndex: Int, tf: Int)]] = [:]

    /// term → Set of docIndices（O(1) メンバーシップ判定用）
    private var termDocSets: [String: Set<Int>] = [:]

    /// 各ドキュメントのフィールド別長さ（トークン数）
    private var docLengths: [Int: [String: Int]] = [:]

    /// フィールド別平均ドキュメント長
    private var avgDocLengths: [String: Double] = [:]

    /// ドキュメント数
    private var docCount: Int = 0

    /// インデックス済みアイテム
    private var items: [SearchableItem] = []

    // MARK: - インデックス構築

    func buildIndex(from items: [SearchableItem]) {
        self.items = items
        self.docCount = items.count
        invertedIndex = [:]
        termDocSets = [:]
        docLengths = [:]

        var fieldLengthSums: [String: Int] = [:]

        for (docIndex, item) in items.enumerated() {
            var docFieldLengths: [String: Int] = [:]

            for (fieldName, text) in item.textFields {
                let tokens = tokenize(text)
                docFieldLengths[fieldName] = tokens.count
                fieldLengthSums[fieldName, default: 0] += tokens.count

                // 各トークンの出現回数
                var termFreqs: [String: Int] = [:]
                for token in tokens {
                    termFreqs[token, default: 0] += 1
                }

                // 転置インデックスに追加（フィールド名をプレフィックスとして含める）
                for (term, freq) in termFreqs {
                    let key = "\(fieldName):\(term)"
                    invertedIndex[key, default: []].append((docIndex: docIndex, tf: freq))
                    termDocSets[key, default: []].insert(docIndex)
                }
            }

            docLengths[docIndex] = docFieldLengths
        }

        // 平均ドキュメント長の計算
        for (field, sum) in fieldLengthSums {
            avgDocLengths[field] = docCount > 0 ? Double(sum) / Double(docCount) : 0
        }
    }

    // MARK: - 検索

    func search(
        query: String,
        mode: SearchMatchMode,
        limit: Int = 100
    ) -> [SearchResult] {
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return [] }

        var docScores: [Int: Double] = [:]
        var docFieldScores: [Int: [String: Double]] = [:]

        let fieldNames = Set(items.flatMap { $0.textFields.keys })

        for fieldName in fieldNames {
            let avgDL = avgDocLengths[fieldName] ?? 1.0

            for token in queryTokens {
                let key = "\(fieldName):\(token)"
                guard let postings = invertedIndex[key] else { continue }

                // IDF: log((N - n(qi) + 0.5) / (n(qi) + 0.5) + 1)
                let n = Double(postings.count)
                let N = Double(docCount)
                let idf = log((N - n + 0.5) / (n + 0.5) + 1.0)

                for posting in postings {
                    let tf = Double(posting.tf)
                    let dl = Double(docLengths[posting.docIndex]?[fieldName] ?? 0)

                    // BM25 score
                    let score = idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * dl / avgDL))

                    docScores[posting.docIndex, default: 0] += score
                    docFieldScores[posting.docIndex, default: [:]][fieldName, default: 0] += score
                }
            }
        }

        // モード別フィルタリング
        let filteredDocIndices: Set<Int>
        switch mode {
        case .all:
            // 全トークンが少なくとも1フィールドに含まれるドキュメント（Set ベース O(1) ルックアップ）
            filteredDocIndices = Set(docScores.keys.filter { docIndex in
                queryTokens.allSatisfy { token in
                    fieldNames.contains { fieldName in
                        let key = "\(fieldName):\(token)"
                        return termDocSets[key]?.contains(docIndex) == true
                    }
                }
            })

        case .any:
            filteredDocIndices = Set(docScores.keys)

        case .phrase:
            // フレーズマッチ: 元のテキストに連続したフレーズが含まれるか
            let phrase = query.lowercased()
            filteredDocIndices = Set(items.indices.filter { idx in
                items[idx].textFields.values.contains { $0.lowercased().contains(phrase) }
            })
        }

        // 結果を構築
        var results: [SearchResult] = []
        for docIndex in filteredDocIndices {
            guard let score = docScores[docIndex], score > 0 else { continue }
            let item = items[docIndex]

            // マッチ範囲の計算
            var matchRanges: [String: [Range<String.Index>]] = [:]
            for (fieldName, text) in item.textFields {
                let lowText = text.lowercased()
                var ranges: [Range<String.Index>] = []
                for token in queryTokens {
                    var searchStart = lowText.startIndex
                    while searchStart < lowText.endIndex,
                          let range = lowText.range(of: token, range: searchStart..<lowText.endIndex) {
                        // 元テキストの対応する範囲
                        let origRange = text.index(text.startIndex, offsetBy: lowText.distance(from: lowText.startIndex, to: range.lowerBound))..<text.index(text.startIndex, offsetBy: lowText.distance(from: lowText.startIndex, to: range.upperBound))
                        ranges.append(origRange)
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
                fieldScores: docFieldScores[docIndex] ?? [:],
                matchRanges: matchRanges
            ))
        }

        results.sort { $0.score > $1.score }
        return Array(results.prefix(limit))
    }

    // MARK: - ファセット集計

    func computeFacets(
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

            // 値が多すぎる（ユニーク値がアイテム数の半分以上）フィールドはスキップ
            let uniqueRatio = Double(counts.count) / Double(max(allItems.count, 1))
            guard uniqueRatio < 0.5, counts.count > 1, counts.count <= 50 else { continue }

            let values = counts
                .sorted { $0.value > $1.value }
                .map { FacetValue(value: $0.key, count: $0.value) }

            facets.append(Facet(fieldName: fieldName, values: values))
        }

        return facets
    }

    // MARK: - トークナイザー

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count >= 2 }
    }
}
