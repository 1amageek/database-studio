import SwiftUI

/// バージョンタイムライン（縦方向）
struct VersionTimelineView: View {
    @Bindable var state: VersionViewState

    var body: some View {
        List {
            Section("Record: \(state.document.recordID)") {
                ForEach(state.sortedVersions) { version in
                    Button {
                        state.selectedVersionID = version.id
                    } label: {
                        timelineRow(version)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Info") {
                LabeledContent("Entity", value: state.document.entityName)
                    .font(.caption)
                LabeledContent("Versions", value: "\(state.document.versions.count)")
                    .font(.caption)
                LabeledContent("Fields", value: "\(state.document.fieldNames.count)")
                    .font(.caption)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - タイムライン行

    private func timelineRow(_ version: VersionEntry) -> some View {
        let isSelected = state.selectedVersionID == version.id
        let isLatest = version.version == state.sortedVersions.first?.version

        return HStack(spacing: 10) {
            // タイムラインドット + ライン
            VStack(spacing: 0) {
                Circle()
                    .fill(isSelected ? Color.accentColor : (isLatest ? .green : .secondary))
                    .frame(width: 10, height: 10)

                if version.version > 1 {
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("v\(version.version)")
                        .font(.callout.weight(isSelected ? .bold : .medium))

                    if isLatest {
                        Text("Current")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Text(state.relativeTime(for: version))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let author = version.author {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(version.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
