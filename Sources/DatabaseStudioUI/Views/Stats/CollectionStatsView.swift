import SwiftUI

/// コレクション統計表示ビュー
public struct CollectionStatsView: View {
    public let stats: CollectionStats

    public init(stats: CollectionStats) {
        self.stats = stats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statRow(label: "Documents", value: formatNumber(stats.documentCount))
            statRow(label: "Storage Size", value: formatBytes(stats.storageSize))
            statRow(label: "Avg Document Size", value: formatBytes(stats.avgDocumentSize))
        }
        .font(.system(.body, design: .monospaced))
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// インデックス統計表示ビュー
public struct IndexStatsView: View {
    public let stats: IndexStats

    public init(stats: IndexStats) {
        self.stats = stats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statRow(label: "Entries", value: formatNumber(stats.entryCount))
            statRow(label: "Storage Size", value: formatBytes(stats.storageSize))
            statRow(label: "Kind", value: stats.kindIdentifier)
        }
        .font(.system(.body, design: .monospaced))
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Previews

#Preview("Collection Stats") {
    CollectionStatsView(stats: CollectionStats(
        typeName: "User",
        documentCount: 12345,
        storageSize: 1024 * 1024 * 5
    ))
    .padding()
    .frame(width: 250)
}

#Preview("Index Stats") {
    IndexStatsView(stats: IndexStats(
        indexName: "User_email_idx",
        kindIdentifier: "scalar",
        entryCount: 12345,
        storageSize: 1024 * 512
    ))
    .padding()
    .frame(width: 250)
}
