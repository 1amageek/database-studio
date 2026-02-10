import SwiftUI

/// フィールド単位の差分表示ビュー
struct VersionDiffView: View {
    let diff: DiffSummary
    let displayMode: DiffDisplayMode
    let oldVersion: VersionEntry?
    let newVersion: VersionEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ヘッダー
                diffHeader
                    .padding()

                Divider()

                // 差分リスト
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredChanges) { change in
                        diffRow(change)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - ヘッダー

    private var diffHeader: some View {
        HStack(spacing: 16) {
            if let old = oldVersion {
                Text("v\(old.version)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("v\(newVersion.version)")
                .font(.callout.weight(.semibold))

            Spacer()

            HStack(spacing: 12) {
                if diff.addedCount > 0 {
                    Label("\(diff.addedCount)", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if diff.removedCount > 0 {
                    Label("\(diff.removedCount)", systemImage: "minus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if diff.modifiedCount > 0 {
                    Label("\(diff.modifiedCount)", systemImage: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - フィルタ済み変更

    private var filteredChanges: [FieldChange] {
        switch displayMode {
        case .changesOnly:
            return diff.changes.filter { change in
                switch change {
                case .unchanged: return false
                default: return true
                }
            }
        case .sideBySide, .fullDiff:
            return diff.changes
        }
    }

    // MARK: - 差分行

    private func diffRow(_ change: FieldChange) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // フィールド名
            Text(change.key)
                .font(.caption.weight(.medium))
                .frame(width: 120, alignment: .trailing)
                .padding(.trailing, 12)
                .foregroundStyle(.secondary)

            // 値
            VStack(alignment: .leading, spacing: 2) {
                switch change {
                case .added(_, let newValue):
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(newValue)
                            .font(.caption)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))

                case .removed(_, let oldValue):
                    HStack(spacing: 4) {
                        Image(systemName: "minus")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text(oldValue)
                            .font(.caption)
                            .strikethrough()
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))

                case .modified(_, let oldValue, let newValue):
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Image(systemName: "minus")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            Text(oldValue)
                                .font(.caption)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 1)
                        .padding(.horizontal, 6)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))

                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text(newValue)
                                .font(.caption)
                        }
                        .padding(.vertical, 1)
                        .padding(.horizontal, 6)
                        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                    }

                case .unchanged(_, let value):
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal)
    }
}
