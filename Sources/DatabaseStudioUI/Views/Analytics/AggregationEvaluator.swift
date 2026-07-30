import Foundation

/// Evaluates aggregation queries over an in-memory record snapshot.
enum AggregationEvaluator {

    /// Evaluates a query and returns its panel results.
    static func evaluate(
        _ query: AggregationQuery,
        over records: [[String: Any]]
    ) -> [AggregationResult] {
        if let groupByField = query.groupByField, !groupByField.isEmpty {
            return evaluateGroups(query, over: records, groupedBy: groupByField)
        } else {
            return evaluateScalar(query, over: records)
        }
    }

    // MARK: - Scalar Aggregation

    private static func evaluateScalar(
        _ query: AggregationQuery,
        over records: [[String: Any]]
    ) -> [AggregationResult] {
        let value: Double

        switch query.function {
        case .count:
            value = Double(records.count)

        case .sum:
            guard let fieldName = query.fieldName else { return [] }
            value = records.reduce(into: 0.0) { sum, record in
                if let numericValue = numericValue(from: record[fieldName]) {
                    sum += numericValue
                }
            }

        case .avg:
            guard let fieldName = query.fieldName else { return [] }
            var sum: Double = 0
            var count: Int = 0
            for record in records {
                if let numericValue = numericValue(from: record[fieldName]) {
                    sum += numericValue
                    count += 1
                }
            }
            guard count > 0 else { return [] }
            value = sum / Double(count)

        case .min:
            guard let fieldName = query.fieldName else { return [] }
            var minimumValue = Double.infinity
            for record in records {
                if let numericValue = numericValue(from: record[fieldName]), numericValue < minimumValue {
                    minimumValue = numericValue
                }
            }
            guard minimumValue.isFinite else { return [] }
            value = minimumValue

        case .max:
            guard let fieldName = query.fieldName else { return [] }
            var maximumValue = -Double.infinity
            for record in records {
                if let numericValue = numericValue(from: record[fieldName]), numericValue > maximumValue {
                    maximumValue = numericValue
                }
            }
            guard maximumValue.isFinite else { return [] }
            value = maximumValue

        case .percentile:
            guard let fieldName = query.fieldName else { return [] }
            let values = records.compactMap { numericValue(from: $0[fieldName]) }.sorted()
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

    // MARK: - Grouped Aggregation

    private static func evaluateGroups(
        _ query: AggregationQuery,
        over records: [[String: Any]],
        groupedBy groupField: String
    ) -> [AggregationResult] {
        // Positions retain the source records without copying their dictionaries.
        var recordIndicesByGroup: [String: [Int]] = [:]
        for (recordIndex, record) in records.enumerated() {
            let groupKey: String
            if let fieldValue = record[groupField] {
                groupKey = String(describing: fieldValue)
            } else {
                groupKey = "(null)"
            }
            recordIndicesByGroup[groupKey, default: []].append(recordIndex)
        }

        var results: [AggregationResult] = []
        results.reserveCapacity(recordIndicesByGroup.count)

        for (groupKey, recordIndices) in recordIndicesByGroup.sorted(by: { $0.key < $1.key }) {
            let value: Double

            switch query.function {
            case .count:
                value = Double(recordIndices.count)

            case .sum:
                guard let fieldName = query.fieldName else { continue }
                value = recordIndices.reduce(into: 0.0) { sum, recordIndex in
                    if let numericValue = numericValue(from: records[recordIndex][fieldName]) {
                        sum += numericValue
                    }
                }

            case .avg:
                guard let fieldName = query.fieldName else { continue }
                var sum: Double = 0
                var count: Int = 0
                for recordIndex in recordIndices {
                    if let numericValue = numericValue(from: records[recordIndex][fieldName]) {
                        sum += numericValue
                        count += 1
                    }
                }
                guard count > 0 else { continue }
                value = sum / Double(count)

            case .min:
                guard let fieldName = query.fieldName else { continue }
                var minimumValue = Double.infinity
                for recordIndex in recordIndices {
                    if let numericValue = numericValue(from: records[recordIndex][fieldName]),
                       numericValue < minimumValue {
                        minimumValue = numericValue
                    }
                }
                guard minimumValue.isFinite else { continue }
                value = minimumValue

            case .max:
                guard let fieldName = query.fieldName else { continue }
                var maximumValue = -Double.infinity
                for recordIndex in recordIndices {
                    if let numericValue = numericValue(from: records[recordIndex][fieldName]),
                       numericValue > maximumValue {
                        maximumValue = numericValue
                    }
                }
                guard maximumValue.isFinite else { continue }
                value = maximumValue

            case .percentile:
                guard let fieldName = query.fieldName else { continue }
                let values = recordIndices.compactMap {
                    numericValue(from: records[$0][fieldName])
                }.sorted()
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

    // MARK: - Numeric Values

    private static func numericValue(from value: Any?) -> Double? {
        guard let value else { return nil }
        if let doubleValue = value as? Double { return doubleValue }
        if let floatValue = value as? Float { return Double(floatValue) }
        if let integerValue = value as? Int { return Double(integerValue) }
        if let integerValue = value as? Int64 { return Double(integerValue) }
        if let unsignedValue = value as? UInt { return Double(unsignedValue) }
        if let stringValue = value as? String { return Double(stringValue) }
        return nil
    }
}
