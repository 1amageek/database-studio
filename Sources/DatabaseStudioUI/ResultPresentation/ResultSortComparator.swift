import Foundation
import DatabaseKit

/// Orders loaded rows using canonical values, without parsing formatted cells.
struct ResultSortComparator: SortComparator {
    var column: Int
    var order: Foundation.SortOrder = .forward

    static func field(_ value: DatabaseKit.QueryValue) -> FieldValue? {
        switch value {
        case .primitive(let value): value
        case .numeric(let value): .decimal(value.value)
        default: nil
        }
    }

    func compare(_ lhs: ResultPageRow, _ rhs: ResultPageRow) -> ComparisonResult {
        let result: ComparisonResult
        if column < 0 {
            result = lhs.id == rhs.id ? .orderedSame : lhs.id < rhs.id ? .orderedAscending : .orderedDescending
        } else {
            if let left = Self.field(lhs.values[column]), let right = Self.field(rhs.values[column]) {
                result = left == right ? .orderedSame : left < right ? .orderedAscending : .orderedDescending
            } else { result = .orderedSame }
        }
        return order == .forward ? result : result == .orderedAscending ? .orderedDescending : result == .orderedDescending ? .orderedAscending : .orderedSame
    }
}
