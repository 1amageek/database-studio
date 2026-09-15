import SwiftUI
import DatabaseKit

/// Displays one index in a compact summary row.
struct CompactIndexRow: View {
    let index: IndexDescriptor

    var body: some View {
        HStack {
            Image(systemName: index.type.symbolName)
                .foregroundStyle(color(for: index.type))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(index.name)
                    .font(.system(.body, design: .monospaced))

                HStack(spacing: 4) {
                    Text(index.type.displayName)
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

    private func color(for type: IndexType) -> Color {
        switch type {
        case .ordered: .blue
        case .aggregate: .orange
        case .updateCount: .orange
        case .history: .brown
        case .bitmap: .indigo
        case .leaderboard: .mint
        case .vector: .green
        case .text: .cyan
        case .spatial: .teal
        case .rank: .yellow
        case .graph: .pink
        case .custom: .gray
        }
    }
}

#Preview("Index Row Compact") {
    let fields = [
        FieldSchema(name: "email", fieldNumber: 1, type: .string),
        FieldSchema(name: "embedding", fieldNumber: 2, type: .vector),
    ]
    VStack {
        CompactIndexRow(
            index: try! IndexDescriptor(
                entityName: "User",
                declaration: .ordered(
                    name: "email_idx",
                    keys: [.ascending(.init(name: "email", number: 1))]
                ),
                fieldSchemas: fields
            )
        )
        CompactIndexRow(
            index: try! IndexDescriptor(
                entityName: "User",
                declaration: .vector(
                    name: "embedding_idx",
                    embedding: .init(name: "embedding", number: 2),
                    dimensions: 384
                ),
                fieldSchemas: fields
            )
        )
    }
    .padding()
    .frame(width: 300)
}
