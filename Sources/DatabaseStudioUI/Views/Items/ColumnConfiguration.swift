import SwiftUI

/// テーブルカラムの種類
public enum ColumnType: String, Codable, CaseIterable, Identifiable, Sendable {
    case id = "ID"
    case preview = "Preview"
    case size = "Size"

    public var id: String { rawValue }

    public var label: String { rawValue }

    public var symbolName: String {
        switch self {
        case .id: return "number"
        case .preview: return "text.alignleft"
        case .size: return "internaldrive"
        }
    }
}

/// テーブルカラム設定
public struct ColumnConfig: Codable, Equatable, Sendable {
    public var visibleColumns: [ColumnType]
    public var jsonFieldColumns: [String]

    public init(
        visibleColumns: [ColumnType] = ColumnType.allCases,
        jsonFieldColumns: [String] = []
    ) {
        self.visibleColumns = visibleColumns
        self.jsonFieldColumns = jsonFieldColumns
    }

    public static let `default` = ColumnConfig()

    public var allColumnCount: Int {
        visibleColumns.count + jsonFieldColumns.count
    }
}

/// カラム設定ポップオーバー
struct ColumnConfigurationView: View {
    @Binding var config: ColumnConfig
    let availableFields: [DiscoveredField]

    @State private var newFieldPath = ""
    @State private var showingFieldPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 標準カラム
            VStack(alignment: .leading, spacing: 8) {
                Text("Standard Columns")
                    .font(.headline)

                ForEach(ColumnType.allCases) { columnType in
                    Toggle(isOn: Binding(
                        get: { config.visibleColumns.contains(columnType) },
                        set: { isOn in
                            if isOn {
                                if !config.visibleColumns.contains(columnType) {
                                    config.visibleColumns.append(columnType)
                                }
                            } else {
                                config.visibleColumns.removeAll { $0 == columnType }
                            }
                        }
                    )) {
                        Label(columnType.label, systemImage: columnType.symbolName)
                    }
                    .toggleStyle(.checkbox)
                }
            }

            Divider()

            // JSONフィールドカラム
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("JSON Field Columns")
                        .font(.headline)

                    Spacer()

                    Button {
                        showingFieldPicker = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showingFieldPicker) {
                        fieldPickerContent
                    }
                }

                if config.jsonFieldColumns.isEmpty {
                    Text("No custom columns")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(config.jsonFieldColumns, id: \.self) { fieldPath in
                        HStack {
                            Image(systemName: "chevron.right.2")
                                .foregroundStyle(.secondary)
                            Text(fieldPath)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                config.jsonFieldColumns.removeAll { $0 == fieldPath }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Divider()

            // リセットボタン
            Button("Reset to Default") {
                config = .default
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .frame(minWidth: 250)
    }

    @ViewBuilder
    private var fieldPickerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Field Column")
                .font(.headline)
                .padding(.bottom, 4)

            if availableFields.isEmpty {
                Text("No fields discovered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(availableFields, id: \.path) { field in
                            Button {
                                if !config.jsonFieldColumns.contains(field.path) {
                                    config.jsonFieldColumns.append(field.path)
                                }
                                showingFieldPicker = false
                            } label: {
                                HStack {
                                    Text(field.path)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Text(field.inferredType.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                config.jsonFieldColumns.contains(field.path)
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                            .cornerRadius(4)
                            .disabled(config.jsonFieldColumns.contains(field.path))
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            // 手動入力
            HStack {
                TextField("Field path (e.g., user.name)", text: $newFieldPath)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    let path = newFieldPath.trimmingCharacters(in: .whitespaces)
                    if !path.isEmpty && !config.jsonFieldColumns.contains(path) {
                        config.jsonFieldColumns.append(path)
                        newFieldPath = ""
                    }
                }
                .disabled(newFieldPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }
}

// MARK: - Previews

#Preview("Column Configuration") {
    @Previewable @State var config = ColumnConfig.default
    ColumnConfigurationView(
        config: $config,
        availableFields: [
            DiscoveredField(path: "name", name: "name", inferredType: .string, sampleValues: [], depth: 0),
            DiscoveredField(path: "email", name: "email", inferredType: .string, sampleValues: [], depth: 0),
            DiscoveredField(path: "age", name: "age", inferredType: .number, sampleValues: [], depth: 0),
            DiscoveredField(path: "isActive", name: "isActive", inferredType: .boolean, sampleValues: [], depth: 0),
        ]
    )
    .frame(width: 300, height: 400)
}
