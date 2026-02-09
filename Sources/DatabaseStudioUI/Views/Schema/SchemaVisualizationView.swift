import SwiftUI
import Core

/// スキーマ可視化ビュー
public struct SchemaVisualizationView: View {
    let entity: Schema.Entity?
    @Environment(\.dismiss) private var dismiss
    @State private var zoomLevel: CGFloat = 1.0

    public init(entity: Schema.Entity?) {
        self.entity = entity
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let entity = entity {
                    ScrollView([.horizontal, .vertical]) {
                        schemaContent(entity: entity)
                            .scaleEffect(zoomLevel)
                            .frame(minWidth: 600, minHeight: 400)
                    }
                } else {
                    emptyStateView
                }
            }
            .navigationTitle(entity.map { "Schema: \($0.name)" } ?? "Schema")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if entity != nil {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            withAnimation { zoomLevel = max(0.5, zoomLevel - 0.1) }
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }

                        Text("\(Int(zoomLevel * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 40)

                        Button {
                            withAnimation { zoomLevel = min(2.0, zoomLevel + 0.1) }
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }

                        Button {
                            withAnimation { zoomLevel = 1.0 }
                        } label: {
                            Image(systemName: "1.magnifyingglass")
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 750, minHeight: 400, idealHeight: 550)
    }

    // MARK: - Schema Content

    @ViewBuilder
    private func schemaContent(entity: Schema.Entity) -> some View {
        HStack(alignment: .top, spacing: 40) {
            // Fields column
            VStack(alignment: .leading, spacing: 16) {
                Text("Fields")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                FieldsCard(entity: entity)
            }
            .padding()

            // Indexes column
            VStack(alignment: .leading, spacing: 16) {
                Text("Indexes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ForEach(entity.indexes, id: \.name) { index in
                    IndexCard(index: index)
                }
            }
            .padding()
        }
        .padding()
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Schema")
                .font(.headline)

            Text("Select an entity to view its schema")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Fields Card

private struct FieldsCard: View {
    let entity: Schema.Entity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Entity header
            HStack {
                Image(systemName: "cube.box.fill")
                    .foregroundStyle(.blue)
                Text(entity.name)
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Fields
            ForEach(entity.fields, id: \.name) { field in
                HStack(spacing: 8) {
                    Image(systemName: field.type.iconName)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(field.name)
                        .font(.system(.caption, design: .monospaced))
                    Spacer()
                    Text(field.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Directory info
            if entity.hasDynamicPartition {
                Divider()
                HStack {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Dynamic: \(entity.dynamicFieldNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 250)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Index Card

private struct IndexCard: View {
    let index: AnyIndexDescriptor

    var body: some View {
        HStack(spacing: 12) {
            // Kind icon
            Image(systemName: index.kind.symbolName)
                .foregroundStyle(kindColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(index.name)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(index.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !index.fieldNames.isEmpty {
                        Text(index.fieldNames.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if index.unique {
                Text("UNIQUE")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var kindColor: Color {
        switch index.kind.subspaceStructure {
        case .flat: return .blue
        case .aggregation: return .green
        case .hierarchical: return .purple
        }
    }
}

// MARK: - Preview

#Preview {
    SchemaVisualizationView(entity: Schema.Entity(
        name: "User",
        fields: [
            FieldSchema(name: "id", fieldNumber: 1, type: .string),
            FieldSchema(name: "name", fieldNumber: 2, type: .string),
            FieldSchema(name: "email", fieldNumber: 3, type: .string),
            FieldSchema(name: "age", fieldNumber: 4, type: .int64),
        ],
        directoryComponents: [.staticPath("app"), .staticPath("users")],
        indexes: [
            AnyIndexDescriptor(
                name: "user_email_idx",
                kind: AnyIndexKind(identifier: "scalar", subspaceStructure: .flat, fieldNames: ["email"], metadata: [:]),
                commonMetadata: ["unique": .bool(true)]
            ),
            AnyIndexDescriptor(
                name: "user_age_idx",
                kind: AnyIndexKind(identifier: "scalar", subspaceStructure: .flat, fieldNames: ["age"], metadata: [:]),
                commonMetadata: [:]
            ),
        ]
    ))
}
