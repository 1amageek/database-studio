import Foundation

/// メモリ内集約エンジン
enum AggregationEngine {

    /// 集約クエリを実行してパネル結果を返す
    static func execute(
        query: AggregationQuery,
        items: [[String: Any]]
    ) -> [AggregationResult] {
        if let groupByField = query.groupByField, !groupByField.isEmpty {
            return executeGrouped(query: query, items: items, groupByField: groupByField)
        } else {
            return executeScalar(query: query, items: items)
        }
    }

    // MARK: - スカラー集約（GROUP BY なし）

    private static func executeScalar(
        query: AggregationQuery,
        items: [[String: Any]]
    ) -> [AggregationResult] {
        let value: Double

        switch query.function {
        case .count:
            value = Double(items.count)

        case .sum:
            guard let fieldName = query.fieldName else { return [] }
            value = items.reduce(into: 0.0) { sum, item in
                if let v = extractDouble(item[fieldName]) { sum += v }
            }

        case .avg:
            guard let fieldName = query.fieldName else { return [] }
            var sum: Double = 0
            var count: Int = 0
            for item in items {
                if let v = extractDouble(item[fieldName]) {
                    sum += v
                    count += 1
                }
            }
            guard count > 0 else { return [] }
            value = sum / Double(count)

        case .min:
            guard let fieldName = query.fieldName else { return [] }
            var minVal = Double.infinity
            for item in items {
                if let v = extractDouble(item[fieldName]), v < minVal {
                    minVal = v
                }
            }
            guard minVal.isFinite else { return [] }
            value = minVal

        case .max:
            guard let fieldName = query.fieldName else { return [] }
            var maxVal = -Double.infinity
            for item in items {
                if let v = extractDouble(item[fieldName]), v > maxVal {
                    maxVal = v
                }
            }
            guard maxVal.isFinite else { return [] }
            value = maxVal

        case .percentile:
            guard let fieldName = query.fieldName else { return [] }
            let values = items.compactMap { extractDouble($0[fieldName]) }.sorted()
            guard !values.isEmpty else { return [] }
            let index = Int(Double(values.count - 1) * query.percentileValue)
            value = values[Swift.min(index, values.count - 1)]
        }

        return [AggregationResult(
            groupKey: "Total",
            value: value,
            label: query.label
        )]
    }

    // MARK: - グループ集約（インデックスベース — コピー回避）

    private static func executeGrouped(
        query: AggregationQuery,
        items: [[String: Any]],
        groupByField: String
    ) -> [AggregationResult] {
        // インデックスベースのグループ化（辞書コピー回避）
        var groupIndices: [String: [Int]] = [:]
        for (i, item) in items.enumerated() {
            let key: String
            if let v = item[groupByField] {
                key = String(describing: v)
            } else {
                key = "(null)"
            }
            groupIndices[key, default: []].append(i)
        }

        // 各グループを集約
        var results: [AggregationResult] = []
        results.reserveCapacity(groupIndices.count)

        for (groupKey, indices) in groupIndices.sorted(by: { $0.key < $1.key }) {
            let value: Double

            switch query.function {
            case .count:
                value = Double(indices.count)

            case .sum:
                guard let fieldName = query.fieldName else { continue }
                value = indices.reduce(into: 0.0) { sum, idx in
                    if let v = extractDouble(items[idx][fieldName]) { sum += v }
                }

            case .avg:
                guard let fieldName = query.fieldName else { continue }
                var sum: Double = 0
                var count: Int = 0
                for idx in indices {
                    if let v = extractDouble(items[idx][fieldName]) {
                        sum += v
                        count += 1
                    }
                }
                guard count > 0 else { continue }
                value = sum / Double(count)

            case .min:
                guard let fieldName = query.fieldName else { continue }
                var minVal = Double.infinity
                for idx in indices {
                    if let v = extractDouble(items[idx][fieldName]), v < minVal {
                        minVal = v
                    }
                }
                guard minVal.isFinite else { continue }
                value = minVal

            case .max:
                guard let fieldName = query.fieldName else { continue }
                var maxVal = -Double.infinity
                for idx in indices {
                    if let v = extractDouble(items[idx][fieldName]), v > maxVal {
                        maxVal = v
                    }
                }
                guard maxVal.isFinite else { continue }
                value = maxVal

            case .percentile:
                guard let fieldName = query.fieldName else { continue }
                let values = indices.compactMap { extractDouble(items[$0][fieldName]) }.sorted()
                guard !values.isEmpty else { continue }
                let index = Int(Double(values.count - 1) * query.percentileValue)
                value = values[Swift.min(index, values.count - 1)]
            }

            results.append(AggregationResult(
                groupKey: groupKey,
                value: value,
                label: groupKey
            ))
        }

        return results
    }

    // MARK: - 型変換

    private static func extractDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let d = value as? Double { return d }
        if let f = value as? Float { return Double(f) }
        if let i = value as? Int { return Double(i) }
        if let i = value as? Int64 { return Double(i) }
        if let u = value as? UInt { return Double(u) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
