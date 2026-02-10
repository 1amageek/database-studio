import SwiftUI

/// バージョン詳細インスペクター
struct VersionInspectorView: View {
    let version: VersionEntry
    let diff: DiffSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metadataSection
                changesSection
                snapshotSection
            }
            .padding()
        }
    }

    // MARK: - メタデータ

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Version \(version.version)", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Timestamp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(version.timestamp, format: .dateTime)
                        .font(.caption)
                }
                if let author = version.author {
                    GridRow {
                        Text("Author")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(author)
                            .font(.caption)
                    }
                }
                GridRow {
                    Text("Fields")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(version.snapshot.count)")
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    // MARK: - 変更サマリー

    @ViewBuilder
    private var changesSection: some View {
        if let diff {
            VStack(alignment: .leading, spacing: 8) {
                Text("Changes")
                    .font(.subheadline.weight(.semibold))

                if diff.hasChanges {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        if diff.addedCount > 0 {
                            GridRow {
                                Circle().fill(.green).frame(width: 8, height: 8)
                                Text("Added: \(diff.addedCount)")
                                    .font(.caption)
                            }
                        }
                        if diff.removedCount > 0 {
                            GridRow {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                Text("Removed: \(diff.removedCount)")
                                    .font(.caption)
                            }
                        }
                        if diff.modifiedCount > 0 {
                            GridRow {
                                Circle().fill(.orange).frame(width: 8, height: 8)
                                Text("Modified: \(diff.modifiedCount)")
                                    .font(.caption)
                            }
                        }
                    }
                } else {
                    Text("No changes from previous version")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - スナップショット

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Snapshot")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(version.snapshot.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    GridRow {
                        Text(key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 80, alignment: .trailing)
                        Text(value)
                            .font(.caption)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
