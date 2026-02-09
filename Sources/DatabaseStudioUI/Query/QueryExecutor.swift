import Foundation

/// Executes queries against DecodedItem collections (client-side filtering)
public struct QueryExecutor {

    /// Filter items based on query
    public static func filter(_ items: [DecodedItem], with query: ItemQuery) -> [DecodedItem] {
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
            guard let str = fieldValue as? String,
                  case .string(let searchStr) = condition.value else { return false }
            return str.localizedCaseInsensitiveContains(searchStr)
        case .hasPrefix:
            guard let str = fieldValue as? String,
                  case .string(let prefix) = condition.value else { return false }
            return str.lowercased().hasPrefix(prefix.lowercased())
        case .hasSuffix:
            guard let str = fieldValue as? String,
                  case .string(let suffix) = condition.value else { return false }
            return str.lowercased().hasSuffix(suffix.lowercased())
        }
    }

    private static func resolveFieldPath(_ path: String, in json: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = json

        for component in components {
            guard let dict = current as? [String: Any],
                  let next = dict[component] else {
                return nil
            }
            current = next
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
        case (let s as String, .string(let r)):
            return s.localizedCaseInsensitiveCompare(r)
        case (let n as NSNumber, .number(let r)):
            let d = n.doubleValue
            if d < r { return .orderedAscending }
            if d > r { return .orderedDescending }
            return .orderedSame
        case (let n as NSNumber, .string(let r)):
            if let rNum = Double(r) {
                let d = n.doubleValue
                if d < rNum { return .orderedAscending }
                if d > rNum { return .orderedDescending }
                return .orderedSame
            }
            return String(describing: n).localizedCaseInsensitiveCompare(r)
        case (let s as String, .number(let r)):
            if let lNum = Double(s) {
                if lNum < r { return .orderedAscending }
                if lNum > r { return .orderedDescending }
                return .orderedSame
            }
            return .orderedAscending
        case (let b as Bool, .boolean(let r)):
            if b == r { return .orderedSame }
            return b ? .orderedDescending : .orderedAscending
        case (let n as NSNumber, .boolean(let r)) where CFGetTypeID(n) == CFBooleanGetTypeID():
            let b = n.boolValue
            if b == r { return .orderedSame }
            return b ? .orderedDescending : .orderedAscending
        case (_, .null):
            return .orderedDescending
        default:
            let lhsStr = String(describing: lhs)
            if case .string(let r) = rhs {
                return lhsStr.localizedCaseInsensitiveCompare(r)
            }
            return .orderedAscending
        }
    }
}
