import Foundation
import DatabaseKit

/// A draft scalar condition converted to the server's canonical expression.
struct RuntimeRecordFilter {
    enum ValueType: String, CaseIterable {
        case string, int64, uint64, double, boolean
    }

    enum ValidationError: Error, LocalizedError {
        case invalidValue(ValueType)
        case unsupportedOperator

        var errorDescription: String? {
            switch self {
            case .invalidValue(let type): return "Enter a valid \(type.rawValue) value."
            case .unsupportedOperator: return "Use the query editor for this comparison."
            }
        }
    }

    static let comparisons: [QueryOperator] = [
        .equal, .notEqual, .greaterThan, .greaterThanOrEqual,
        .lessThan, .lessThanOrEqual, .isNull, .isNotNull
    ]
    var field = ""
    var comparison: QueryOperator = .equal
    var valueType: ValueType = .string
    var text = ""

    func expression() throws -> DatabaseKit.Expression? {
        guard !field.isEmpty else { return nil }
        let column = DatabaseKit.Expression.column(ColumnRef(field))
        if comparison == .isNull { return .isNull(column) }
        if comparison == .isNotNull { return .isNotNull(column) }
        let literal: Literal
        switch valueType {
        case .string: literal = .string(text)
        case .int64:
            guard let value = Int64(text) else { throw ValidationError.invalidValue(valueType) }
            literal = .int(value)
        case .uint64:
            guard let value = UInt64(text) else { throw ValidationError.invalidValue(valueType) }
            literal = .uint(value)
        case .double:
            guard let value = Double(text), value.isFinite else { throw ValidationError.invalidValue(valueType) }
            literal = .double(value)
        case .boolean:
            guard let value = Bool(text) else { throw ValidationError.invalidValue(valueType) }
            literal = .bool(value)
        }
        let value = DatabaseKit.Expression.literal(literal)
        switch comparison {
        case .equal: return .equal(column, value)
        case .notEqual: return .notEqual(column, value)
        case .greaterThan: return .greaterThan(column, value)
        case .greaterThanOrEqual: return .greaterThanOrEqual(column, value)
        case .lessThan: return .lessThan(column, value)
        case .lessThanOrEqual: return .lessThanOrEqual(column, value)
        default: throw ValidationError.unsupportedOperator
        }
    }
}
