import SwiftUI
import DatabaseKit

/// Displays the complete logical definition of one schema index.
public struct IndexDetailView: View {
    let index: IndexDescriptor

    public init(index: IndexDescriptor) {
        self.index = index
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                fieldsSection

                if !index.configurationDisplay.isEmpty {
                    Divider()
                    configurationSection
                }

                Divider()
                optionsSection
            }
            .padding()
        }
        .navigationTitle(index.name)
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: index.type.symbolName)
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(index.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    Text(index.type.displayName)
                    Text("--")
                    Text("\(index.fieldNames.count) key field(s)")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Key Fields", systemImage: "list.bullet")
                .font(.headline)

            if index.keys.isEmpty {
                Text("No key fields configured")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(index.keys.enumerated()), id: \.offset) {
                        entry in
                        let key = entry.element
                        HStack {
                            Image(
                                systemName: key.order == .ascending
                                    ? "arrow.up"
                                    : "arrow.down"
                            )
                            .foregroundStyle(.secondary)
                            Text(key.field.name)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Configuration", systemImage: "gearshape")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(
                    index.configurationDisplay.sorted(by: { $0.key < $1.key }),
                    id: \.key
                ) { entry in
                    HStack {
                        Text(entry.key)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.value)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Options", systemImage: "slider.horizontal.3")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Unique")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(index.isUnique ? "Yes" : "No")
                        .font(.system(.body, design: .monospaced))
                }

                if !index.includedFieldNames.isEmpty {
                    HStack(alignment: .top) {
                        Text("Included Fields")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(index.includedFieldNames.joined(separator: ", "))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }
}

#Preview("Index Detail") {
    let fields = [
        FieldSchema(name: "email", fieldNumber: 1, type: .string),
    ]
    IndexDetailView(
        index: try! IndexDescriptor(
            entityName: "User",
            declaration: .ordered(
                name: "user_email_idx",
                keys: [.ascending(.init(name: "email", number: 1))],
                unique: true
            ),
            fieldSchemas: fields
        )
    )
    .frame(width: 600, height: 700)
}
