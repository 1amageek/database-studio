import SwiftUI
import DatabaseKit

/// Displays one index in a compact summary row.
struct CompactIndexRow: View {
    let index: IndexDescriptorMetadata

    var body: some View {
        HStack {
            Image(systemName: index.kind.symbolName)
                .foregroundStyle(color(for: index.kind))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(index.name)
                    .font(.system(.body, design: .monospaced))

                HStack(spacing: 4) {
                    Text(index.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !index.fieldNames.isEmpty {
                        Text("(\(index.fieldNames.joined(separator: ", ")))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func color(for kind: IndexKindMetadata) -> Color {
        switch kind.identifier {
        case "scalar": return .blue
        case "count", "sum", "average": return .orange
        case "min", "max": return .purple
        case "vector": return .green
        case "fullText": return .cyan
        case "spatial": return .teal
        case "graph": return .pink
        case "rank": return .yellow
        case "bitmap": return .indigo
        case "version": return .brown
        case "leaderboard": return .mint
        default: return .gray
        }
    }
}

// MARK: - Previews

#Preview("Index Row Compact") {
    VStack {
        CompactIndexRow(index: IndexDescriptorMetadata(
            entityName: "User",
            name: "email_idx",
            kind: IndexKindMetadata(
                identifier: "scalar",
                subspaceStructure: .flat,
                fields: [IndexFieldMetadata(identity: FieldIdentity(name: "email", number: 1))],
                metadata: [:]
            )
        ))
        CompactIndexRow(index: IndexDescriptorMetadata(
            entityName: "User",
            name: "embedding_idx",
            kind: IndexKindMetadata(
                identifier: "vector",
                subspaceStructure: .hierarchical,
                fields: [IndexFieldMetadata(identity: FieldIdentity(name: "embedding", number: 2))],
                metadata: ["dimensions": .int64(384), "metric": .string("cosine")]
            )
        ))
        CompactIndexRow(index: IndexDescriptorMetadata(
            entityName: "User",
            name: "user_count",
            kind: IndexKindMetadata(
                identifier: "count",
                subspaceStructure: .aggregation,
                fields: [],
                metadata: [:]
            )
        ))
    }
    .padding()
    .frame(width: 300)
}
