import Foundation

/// Orders loaded rows using canonical values, without parsing formatted cells.
struct ResultSortComparator: SortComparator {
    var column: Int
    var order: Foundation.SortOrder = .forward

    func compare(_ lhs: ResultPageRow, _ rhs: ResultPageRow) -> ComparisonResult {
        let result: ComparisonResult
        if column < 0 {
            result = lhs.id == rhs.id ? .orderedSame : lhs.id < rhs.id ? .orderedAscending : .orderedDescending
        } else {
            let left = lhs.values[column], right = rhs.values[column]
            result = left == right ? .orderedSame : left < right ? .orderedAscending : .orderedDescending
        }
        return order == .forward ? result : result == .orderedAscending ? .orderedDescending : result == .orderedDescending ? .orderedAscending : .orderedSame
    }
}
