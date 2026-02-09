import Foundation

/// Represents a comparison operator for query conditions
public enum QueryOperator: String, CaseIterable, Codable, Sendable {
    case equal = "="
    case notEqual = "!="
    case contains = "contains"
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case isNull = "is null"
    case isNotNull = "is not null"
    case hasPrefix = "starts with"
    case hasSuffix = "ends with"

    public var displayName: String {
        switch self {
        case .equal: return "equals"
        case .notEqual: return "does not equal"
        case .contains: return "contains"
        case .greaterThan: return "greater than"
        case .greaterThanOrEqual: return "greater than or equal"
        case .lessThan: return "less than"
        case .lessThanOrEqual: return "less than or equal"
        case .isNull: return "is null"
        case .isNotNull: return "is not null"
        case .hasPrefix: return "starts with"
        case .hasSuffix: return "ends with"
        }
    }

    public var requiresValue: Bool {
        switch self {
        case .isNull, .isNotNull: return false
        default: return true
        }
    }

    public static var stringOperators: [QueryOperator] {
        [.equal, .notEqual, .contains, .hasPrefix, .hasSuffix, .isNull, .isNotNull]
    }

    public static var numberOperators: [QueryOperator] {
        [.equal, .notEqual, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual, .isNull, .isNotNull]
    }

    public static var booleanOperators: [QueryOperator] {
        [.equal, .notEqual, .isNull, .isNotNull]
    }

    public static var allFieldOperators: [QueryOperator] {
        allCases
    }
}

/// Represents a value in a query condition
public enum QueryValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null

    public init?(from any: Any?) {
        guard let any = any else {
            self = .null
            return
        }
        switch any {
        case let s as String:
            self = .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .boolean(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case is NSNull:
            self = .null
        default:
            return nil
        }
    }

    public var displayString: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f", n)
            }
            return String(n)
        case .boolean(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }

    public var rawString: String {
        switch self {
        case .string(let s): return s
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f", n)
            }
            return String(n)
        case .boolean(let b): return b ? "true" : "false"
        case .null: return ""
        }
    }
}

/// Logical operator for combining conditions
public enum QueryLogicalOperator: String, CaseIterable, Codable, Sendable {
    case and = "AND"
    case or = "OR"

    public var displayName: String {
        switch self {
        case .and: return "all"
        case .or: return "any"
        }
    }
}

/// Represents a single query condition
public struct QueryCondition: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var fieldPath: String
    public var `operator`: QueryOperator
    public var value: QueryValue

    public init(
        id: UUID = UUID(),
        fieldPath: String = "",
        operator: QueryOperator = .equal,
        value: QueryValue = .string("")
    ) {
        self.id = id
        self.fieldPath = fieldPath
        self.operator = `operator`
        self.value = value
    }

    public var isValid: Bool {
        !fieldPath.isEmpty
    }
}

/// Represents a group of conditions combined with a logical operator
public struct QueryConditionGroup: Identifiable, Codable, Sendable {
    public let id: UUID
    public var logicalOperator: QueryLogicalOperator
    public var conditions: [QueryCondition]
    public var nestedGroups: [QueryConditionGroup]

    public init(
        id: UUID = UUID(),
        logicalOperator: QueryLogicalOperator = .and,
        conditions: [QueryCondition] = [],
        nestedGroups: [QueryConditionGroup] = []
    ) {
        self.id = id
        self.logicalOperator = logicalOperator
        self.conditions = conditions
        self.nestedGroups = nestedGroups
    }

    public var isEmpty: Bool {
        validConditions.isEmpty && nestedGroups.allSatisfy(\.isEmpty)
    }

    public var validConditions: [QueryCondition] {
        conditions.filter { $0.isValid }
    }

    public var totalConditionCount: Int {
        validConditions.count + nestedGroups.reduce(0) { $0 + $1.totalConditionCount }
    }
}

/// Root query structure
public struct ItemQuery: Codable, Sendable {
    public var rootGroup: QueryConditionGroup

    public init(rootGroup: QueryConditionGroup = QueryConditionGroup()) {
        self.rootGroup = rootGroup
    }

    public var hasConditions: Bool {
        !rootGroup.isEmpty
    }

    public var conditionCount: Int {
        rootGroup.totalConditionCount
    }
}
