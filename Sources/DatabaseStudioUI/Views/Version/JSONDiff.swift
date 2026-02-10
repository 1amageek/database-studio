import Foundation

/// フィールド単位の変更種別
enum FieldChange: Identifiable {
    case added(key: String, newValue: String)
    case removed(key: String, oldValue: String)
    case modified(key: String, oldValue: String, newValue: String)
    case unchanged(key: String, value: String)

    var id: String {
        switch self {
        case .added(let key, _): return "add-\(key)"
        case .removed(let key, _): return "rem-\(key)"
        case .modified(let key, _, _): return "mod-\(key)"
        case .unchanged(let key, _): return "unc-\(key)"
        }
    }

    var key: String {
        switch self {
        case .added(let key, _): return key
        case .removed(let key, _): return key
        case .modified(let key, _, _): return key
        case .unchanged(let key, _): return key
        }
    }

    var changeType: String {
        switch self {
        case .added: return "added"
        case .removed: return "removed"
        case .modified: return "modified"
        case .unchanged: return "unchanged"
        }
    }
}

/// JSON差分計算結果
struct DiffSummary {
    let changes: [FieldChange]
    let addedCount: Int
    let removedCount: Int
    let modifiedCount: Int

    var hasChanges: Bool {
        addedCount > 0 || removedCount > 0 || modifiedCount > 0
    }
}

/// JSON差分計算エンジン
enum JSONDiff {

    /// 2つのスナップショット間の差分を計算
    static func diff(
        old: [String: String],
        new: [String: String]
    ) -> DiffSummary {
        let allKeys = Set(old.keys).union(Set(new.keys)).sorted()
        var changes: [FieldChange] = []
        var added = 0
        var removed = 0
        var modified = 0

        for key in allKeys {
            let oldValue = old[key]
            let newValue = new[key]

            switch (oldValue, newValue) {
            case (nil, let new?):
                changes.append(.added(key: key, newValue: new))
                added += 1

            case (let old?, nil):
                changes.append(.removed(key: key, oldValue: old))
                removed += 1

            case (let old?, let new?) where old != new:
                changes.append(.modified(key: key, oldValue: old, newValue: new))
                modified += 1

            case (let val?, _):
                changes.append(.unchanged(key: key, value: val))

            default:
                break
            }
        }

        return DiffSummary(
            changes: changes,
            addedCount: added,
            removedCount: removed,
            modifiedCount: modified
        )
    }
}
