import SwiftUI

/// Single condition row with field, operator, and value
struct QueryConditionRowView: View {
    @Binding var condition: QueryCondition
    let availableFields: [DiscoveredField]
    let onDelete: () -> Void

    @State private var showingFieldPicker = false

    private var selectedField: DiscoveredField? {
        availableFields.first { $0.path == condition.fieldPath }
    }

    /// Operators available for the selected field type
    private var availableOperators: [QueryOperator] {
        guard let field = selectedField else {
            return QueryOperator.allFieldOperators
        }
        switch field.inferredType {
        case .string:
            return QueryOperator.stringOperators
        case .number:
            return QueryOperator.numberOperators
        case .boolean:
            return QueryOperator.booleanOperators
        case .array, .vector, .object, .mixed, .unknown:
            return QueryOperator.allFieldOperators
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Field picker
            Button {
                showingFieldPicker = true
            } label: {
                HStack {
                    Text(condition.fieldPath.isEmpty ? "Select field..." : condition.fieldPath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(condition.fieldPath.isEmpty ? .secondary : .primary)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .frame(minWidth: 120, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showingFieldPicker) {
                FieldPickerView(
                    fields: availableFields,
                    selection: $condition.fieldPath
                )
            }

            // Operator picker
            Picker("", selection: $condition.operator) {
                ForEach(availableOperators, id: \.self) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .frame(width: 150)
            .onChange(of: condition.fieldPath) {
                // Reset operator if it's not valid for the new field type
                if !availableOperators.contains(condition.operator) {
                    condition.operator = availableOperators.first ?? .equal
                }
            }

            // Value input (conditional on operator)
            if condition.operator.requiresValue {
                QueryValueInputView(
                    value: $condition.value,
                    field: selectedField
                )
            }

            Spacer()

            // Delete button
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("Condition Row - Empty") {
    @Previewable @State var condition = QueryCondition()
    QueryConditionRowView(
        condition: $condition,
        availableFields: [
            DiscoveredField(path: "name", name: "name", inferredType: .string, sampleValues: [], depth: 0),
            DiscoveredField(path: "age", name: "age", inferredType: .number, sampleValues: [], depth: 0),
        ],
        onDelete: {}
    )
    .padding()
}

#Preview("Condition Row - Filled") {
    @Previewable @State var condition = QueryCondition(
        fieldPath: "name",
        operator: .contains,
        value: .string("test")
    )
    QueryConditionRowView(
        condition: $condition,
        availableFields: [
            DiscoveredField(path: "name", name: "name", inferredType: .string, sampleValues: [], depth: 0),
        ],
        onDelete: {}
    )
    .padding()
}
