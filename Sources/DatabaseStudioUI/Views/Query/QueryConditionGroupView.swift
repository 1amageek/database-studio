import SwiftUI

/// View for a group of conditions with AND/OR logic
struct QueryConditionGroupView: View {
    @Binding var group: QueryConditionGroup
    let availableFields: [DiscoveredField]
    let isRoot: Bool
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Logical operator picker (only show if multiple conditions)
            if group.conditions.count + group.nestedGroups.count > 1 || !isRoot {
                HStack {
                    Text("Match")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $group.logicalOperator) {
                        Text("all").tag(QueryLogicalOperator.and)
                        Text("any").tag(QueryLogicalOperator.or)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Text("of the following:")
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !isRoot {
                        Button(role: .destructive) {
                            onDelete?()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            // Conditions
            ForEach($group.conditions) { $condition in
                QueryConditionRowView(
                    condition: $condition,
                    availableFields: availableFields,
                    onDelete: {
                        group.conditions.removeAll { $0.id == condition.id }
                    }
                )
            }

            // Nested groups
            ForEach($group.nestedGroups) { $nestedGroup in
                GroupBox {
                    QueryConditionGroupView(
                        group: $nestedGroup,
                        availableFields: availableFields,
                        isRoot: false,
                        onDelete: {
                            group.nestedGroups.removeAll { $0.id == nestedGroup.id }
                        }
                    )
                }
                .padding(.leading, 16)
            }

            // Add nested group button
            if !group.conditions.isEmpty {
                Button {
                    group.nestedGroups.append(QueryConditionGroup(conditions: [QueryCondition()]))
                } label: {
                    Label("Add Group", systemImage: "rectangle.stack.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Previews

#Preview("Condition Group - Simple") {
    @Previewable @State var group = QueryConditionGroup(
        conditions: [
            QueryCondition(fieldPath: "name", operator: .contains, value: .string("test")),
        ]
    )
    QueryConditionGroupView(
        group: $group,
        availableFields: [
            DiscoveredField(path: "name", name: "name", inferredType: .string, sampleValues: [], depth: 0),
        ],
        isRoot: true,
        onDelete: nil
    )
    .padding()
}

#Preview("Condition Group - Multiple") {
    @Previewable @State var group = QueryConditionGroup(
        conditions: [
            QueryCondition(fieldPath: "name", operator: .contains, value: .string("test")),
            QueryCondition(fieldPath: "age", operator: .greaterThan, value: .number(18)),
        ]
    )
    QueryConditionGroupView(
        group: $group,
        availableFields: [
            DiscoveredField(path: "name", name: "name", inferredType: .string, sampleValues: [], depth: 0),
            DiscoveredField(path: "age", name: "age", inferredType: .number, sampleValues: [], depth: 0),
        ],
        isRoot: true,
        onDelete: nil
    )
    .padding()
}
