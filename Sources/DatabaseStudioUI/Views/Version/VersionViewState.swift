import SwiftUI

/// Diff 表示モード
enum DiffDisplayMode: String, CaseIterable, Identifiable {
    case changesOnly = "Changes Only"
    case sideBySide = "Side by Side"
    case fullDiff = "Full Diff"

    var id: String { rawValue }
}

/// Version History の状態管理
@Observable @MainActor
final class VersionViewState {

    // MARK: - データ

    var document: VersionDocument

    // MARK: - 選択

    var selectedVersionID: UUID? {
        didSet { computeDiff() }
    }

    var selectedVersion: VersionEntry? {
        guard let id = selectedVersionID else { return nil }
        return document.versions.first { $0.id == id }
    }

    /// 比較先バージョン（選択バージョンの1つ前）
    var comparisonVersion: VersionEntry? {
        guard let selected = selectedVersion else { return nil }
        guard let idx = cachedSortedVersions.firstIndex(where: { $0.id == selected.id }),
              idx + 1 < cachedSortedVersions.count else {
            return nil
        }
        return cachedSortedVersions[idx + 1]
    }

    // MARK: - Diff

    var diffDisplayMode: DiffDisplayMode = .changesOnly
    private(set) var currentDiff: DiffSummary?

    // MARK: - キャッシュ

    /// ソート済みバージョン（キャッシュ）
    private(set) var cachedSortedVersions: [VersionEntry] = []
    private let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var sortedVersions: [VersionEntry] { cachedSortedVersions }

    // MARK: - 初期化

    init(document: VersionDocument) {
        self.document = document
        cachedSortedVersions = document.versions.sorted { $0.version > $1.version }
        // 最新バージョンを選択
        if let latest = cachedSortedVersions.first {
            self.selectedVersionID = latest.id
        }
        computeDiff()
    }

    // MARK: - ドキュメント更新

    func updateDocument(_ newDocument: VersionDocument) {
        document = newDocument
        cachedSortedVersions = newDocument.versions.sorted { $0.version > $1.version }
        computeDiff()
    }

    // MARK: - Diff 計算

    private func computeDiff() {
        guard let selected = selectedVersion else {
            currentDiff = nil
            return
        }

        guard let comparison = comparisonVersion else {
            // 最初のバージョンの場合、全フィールドを "added" として表示
            let changes = selected.snapshot.sorted(by: { $0.key < $1.key }).map { key, value in
                FieldChange.added(key: key, newValue: value)
            }
            currentDiff = DiffSummary(
                changes: changes,
                addedCount: changes.count,
                removedCount: 0,
                modifiedCount: 0
            )
            return
        }

        currentDiff = JSONDiff.diff(
            old: comparison.snapshot,
            new: selected.snapshot
        )
    }

    // MARK: - 相対時間表示

    func relativeTime(for version: VersionEntry) -> String {
        relativeTimeFormatter.localizedString(for: version.timestamp, relativeTo: Date())
    }
}
