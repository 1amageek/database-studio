import SwiftUI
import Core

/// インデックス行（コンパクト）
struct IndexRowCompact: View {
    let index: AnyIndexDescriptor

    var body: some View {
        HStack {
            Image(systemName: index.kind.symbolName)
                .foregroundStyle(colorForKind(index.kind))
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

    private func colorForKind(_ kind: AnyIndexKind) -> Color {
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
        IndexRowCompact(index: AnyIndexDescriptor(
            name: "email_idx",
            kind: AnyIndexKind(identifier: "scalar", subspaceStructure: .flat, fieldNames: ["email"], metadata: [:]),
            commonMetadata: [:]
        ))
        IndexRowCompact(index: AnyIndexDescriptor(
            name: "embedding_idx",
            kind: AnyIndexKind(identifier: "vector", subspaceStructure: .hierarchical, fieldNames: ["embedding"], metadata: ["dimensions": .int(384), "metric": .string("cosine")]),
            commonMetadata: [:]
        ))
        IndexRowCompact(index: AnyIndexDescriptor(
            name: "user_count",
            kind: AnyIndexKind(identifier: "count", subspaceStructure: .aggregation, fieldNames: [], metadata: [:]),
            commonMetadata: [:]
        ))
    }
    .padding()
    .frame(width: 300)
}
