import SwiftUI

/// Popover for selecting a field path
struct FieldPickerView: View {
    let fields: [DiscoveredField]
    @Binding var selection: String
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredFields: [DiscoveredField] {
        // Filter out object types (they're just containers)
        let primitiveFields = fields.filter { $0.inferredType != .object }

        if searchText.isEmpty {
            return primitiveFields
        }
        return primitiveFields.filter {
            $0.path.localizedCaseInsensitiveContains(searchText) ||
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            TextField("Search fields...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()

            Divider()

            // Field list
            List(filteredFields, selection: Binding(
                get: { selection.isEmpty ? nil : selection },
                set: { newValue in
                    if let value = newValue {
                        selection = value
                        dismiss()
                    }
                }
            )) { field in
                FieldRowView(field: field)
                    .tag(field.path)
            }
            .listStyle(.plain)
        }
        .frame(width: 350, height: 300)
    }
}

/// Row view for a single field
private struct FieldRowView: View {
    let field: DiscoveredField

    var body: some View {
        HStack {
            // Indent based on depth
            if field.depth > 0 {
                ForEach(0..<field.depth, id: \.self) { _ in
                    Color.clear.frame(width: 16)
                }
            }

            Image(systemName: field.inferredType.iconName)
                .foregroundStyle(colorForType(field.inferredType))
                .frame(width: 20)

            VStack(alignment: .leading) {
                Text(field.path)
                    .font(.system(.body, design: .monospaced))
                if !field.sampleValues.isEmpty {
                    Text(field.sampleValues.prefix(3).map(\.displayString).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(field.inferredType.rawValue)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
    }

    private func colorForType(_ type: DiscoveredField.FieldType) -> Color {
        switch type {
        case .string: return .green
        case .number: return .blue
        case .boolean: return .orange
        case .array: return .purple
        case .vector: return .cyan
        case .object: return .teal
        case .mixed, .unknown: return .secondary
        }
    }
}

// MARK: - Previews

#Preview("Field Picker") {
    @Previewable @State var selection = ""
    FieldPickerView(
        fields: [
            DiscoveredField(path: "id", name: "id", inferredType: .string, sampleValues: [.string("user_001")], depth: 0),
            DiscoveredField(path: "name", name: "name", inferredType: .string, sampleValues: [.string("John"), .string("Jane")], depth: 0),
            DiscoveredField(path: "age", name: "age", inferredType: .number, sampleValues: [.number(25), .number(30)], depth: 0),
            DiscoveredField(path: "isActive", name: "isActive", inferredType: .boolean, sampleValues: [.boolean(true)], depth: 0),
            DiscoveredField(path: "address", name: "address", inferredType: .object, sampleValues: [], depth: 0),
            DiscoveredField(path: "address.city", name: "city", inferredType: .string, sampleValues: [.string("Tokyo")], depth: 1),
            DiscoveredField(path: "address.zip", name: "zip", inferredType: .string, sampleValues: [.string("100-0001")], depth: 1),
        ],
        selection: $selection
    )
}
