import SwiftUI
import Core

/// インデックス詳細ビュー
public struct IndexDetailView: View {
    let index: AnyIndexDescriptor

    public init(index: AnyIndexDescriptor) {
        self.index = index
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ヘッダー
                headerSection

                Divider()

                // フィールド情報
                fieldsSection

                // メタデータ
                if !index.kind.metadata.isEmpty {
                    Divider()
                    metadataSection
                }

                Divider()

                // Subspace構造
                subspaceStructureSection

                // オプション
                Divider()
                optionsSection
            }
            .padding()
        }
        .navigationTitle(index.name)
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: index.kind.symbolName)
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(index.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    Text(index.kind.displayName)
                    Text("--")
                    Text("\(index.fieldNames.count) field(s)")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Fields", systemImage: "list.bullet")
                .font(.headline)

            if index.fieldNames.isEmpty {
                Text("No fields configured")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(index.fieldNames, id: \.self) { fieldName in
                        HStack {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                            Text(fieldName)
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

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Configuration", systemImage: "gearshape")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(index.kind.metadata.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                    HStack {
                        Text(key)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(metadataValueString(value))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var subspaceStructureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Subspace Structure", systemImage: subspaceStructureSymbol)
                .font(.headline)

            SubspaceStructureView(structure: index.kind.subspaceStructure)
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Options", systemImage: "slider.horizontal.3")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Unique")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(index.unique ? "Yes" : "No")
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("Sparse")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(index.sparse ? "Yes" : "No")
                        .font(.system(.body, design: .monospaced))
                }

                if !index.storedFieldNames.isEmpty {
                    HStack(alignment: .top) {
                        Text("Stored Fields")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(index.storedFieldNames.joined(separator: ", "))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }

    private var subspaceStructureSymbol: String {
        switch index.kind.subspaceStructure {
        case .flat: return "rectangle.split.3x1"
        case .hierarchical: return "point.3.connected.trianglepath.dotted"
        case .aggregation: return "chart.bar"
        }
    }

    private func metadataValueString(_ value: IndexMetadataValue) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return String(format: "%.4f", d)
        case .bool(let b): return b ? "true" : "false"
        case .stringArray(let arr): return arr.joined(separator: ", ")
        case .intArray(let arr): return arr.map(String.init).joined(separator: ", ")
        }
    }
}

// MARK: - Previews

#Preview("Index Detail") {
    IndexDetailView(index: AnyIndexDescriptor(
        name: "user_email_idx",
        kind: AnyIndexKind(
            identifier: "scalar",
            subspaceStructure: .flat,
            fieldNames: ["email"],
            metadata: [:]
        ),
        commonMetadata: [
            "unique": .bool(true),
            "sparse": .bool(false)
        ]
    ))
    .frame(width: 600, height: 700)
}
