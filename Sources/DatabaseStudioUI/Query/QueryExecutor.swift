import Foundation

/// Executes queries against StudioRecord collections (client-side filtering)
public struct QueryExecutor {

    /// Filter items based on query
    public static func filter(_ items: [StudioRecord], with query: ItemQuery) -> [StudioRecord] {
        guard query.hasConditions else { return items }

        return items.filter { item in
            evaluate(group: query.rootGroup, against: item.fields)
        }
    }

    private static func evaluate(group: QueryConditionGroup, against json: [String: Any]) -> Bool {
        let conditionResults = group.conditions
            .filter { $0.isValid }
            .map { evaluate(condition: $0, against: json) }
        let nestedResults = group.nestedGroups.map { evaluate(group: $0, against: json) }
        let allResults = conditionResults + nestedResults

        guard !allResults.isEmpty else { return true }

        switch group.logicalOperator {
        case .and:
            return allResults.allSatisfy { $0 }
        case .or:
            return allResults.contains { $0 }
        }
    }

    private static func evaluate(condition: QueryCondition, against json: [String: Any]) -> Bool {
        let fieldValue = resolveFieldPath(condition.fieldPath, in: json)

        switch condition.operator {
        case .isNull:
            return fieldValue == nil || fieldValue is NSNull
        case .isNotNull:
            return fieldValue != nil && !(fieldValue is NSNull)
        case .equal:
            return compare(fieldValue, to: condition.value) == .orderedSame
        case .notEqual:
            return compare(fieldValue, to: condition.value) != .orderedSame
        case .greaterThan:
            return compare(fieldValue, to: condition.value) == .orderedDescending
        case .greaterThanOrEqual:
            let result = compare(fieldValue, to: condition.value)
            return result == .orderedDescending || result == .orderedSame
        case .lessThan:
            return compare(fieldValue, to: condition.value) == .orderedAscending
        case .lessThanOrEqual:
            let result = compare(fieldValue, to: condition.value)
            return result == .orderedAscending || result == .orderedSame
        case .contains:
            guard let string = fieldValue as? String,
                  case .string(let searchString) = condition.value else { return false }
            return string.localizedCaseInsensitiveContains(searchString)
        case .hasPrefix:
            guard let string = fieldValue as? String,
                  case .string(let prefix) = condition.value else { return false }
            return string.lowercased().hasPrefix(prefix.lowercased())
        case .hasSuffix:
            guard let string = fieldValue as? String,
                  case .string(let suffix) = condition.value else { return false }
            return string.lowercased().hasSuffix(suffix.lowercased())
        }
    }

    private static func resolveFieldPath(_ path: String, in fields: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = fields

        for component in components {
            guard let object = current as? [String: Any],
                  let nestedValue = object[component] else {
                return nil
            }
            current = nestedValue
        }

        return current
    }

    private static func compare(_ lhs: Any?, to rhs: QueryValue) -> ComparisonResult {
        guard let lhs = lhs, !(lhs is NSNull) else {
            if case .null = rhs {
                return .orderedSame
            }
            return .orderedAscending
        }

        switch (lhs, rhs) {
        case (let leftString as String, .string(let rightString)):
            return leftString.localizedCaseInsensitiveCompare(rightString)
        case (let leftNumber as NSNumber, .number(let rightNumber)):
            let leftValue = leftNumber.doubleValue
            if leftValue < rightNumber { return .orderedAscending }
            if leftValue > rightNumber { return .orderedDescending }
            return .orderedSame
        case (let leftNumber as NSNumber, .string(let rightString)):
            if let rightNumber = Double(rightString) {
                let leftValue = leftNumber.doubleValue
                if leftValue < rightNumber { return .orderedAscending }
                if leftValue > rightNumber { return .orderedDescending }
                return .orderedSame
            }
            return String(describing: leftNumber).localizedCaseInsensitiveCompare(rightString)
        case (let leftString as String, .number(let rightNumber)):
            if let leftNumber = Double(leftString) {
                if leftNumber < rightNumber { return .orderedAscending }
                if leftNumber > rightNumber { return .orderedDescending }
                return .orderedSame
            }
            return .orderedAscending
        case (let leftBoolean as Bool, .boolean(let rightBoolean)):
            if leftBoolean == rightBoolean { return .orderedSame }
            return leftBoolean ? .orderedDescending : .orderedAscending
        case (let leftNumber as NSNumber, .boolean(let rightBoolean))
            where CFGetTypeID(leftNumber) == CFBooleanGetTypeID():
            let leftBoolean = leftNumber.boolValue
            if leftBoolean == rightBoolean { return .orderedSame }
            return leftBoolean ? .orderedDescending : .orderedAscending
        case (_, .null):
            return .orderedDescending
        default:
            let leftString = String(describing: lhs)
            if case .string(let rightString) = rhs {
                return leftString.localizedCaseInsensitiveCompare(rightString)
            }
            return .orderedAscending
        }
    }
}
