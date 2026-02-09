import SwiftUI

/// Main query builder popover
struct QueryBuilderView: View {
    @Binding var query: ItemQuery
    let availableFields: [DiscoveredField]
    var typeName: String = ""
    let onApply: () -> Void
    let onClear: () -> Void

    @State private var showingSaveSheet = false
    @State private var showingHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Filter")
                    .font(.headline)

                Spacer()

                // History button
                Button {
                    showingHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderless)
                .help("Saved Queries")

                // Save button
                Button {
                    showingSaveSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(!query.hasConditions)
                .help("Save Query")

                Button("Clear") {
                    onClear()
                }
                .disabled(!query.hasConditions)
            }

            Divider()

            // Condition groups
            ScrollView {
                QueryConditionGroupView(
                    group: $query.rootGroup,
                    availableFields: availableFields,
                    isRoot: true,
                    onDelete: nil
                )
            }
            .frame(maxHeight: 400)

            Divider()

            // Footer with actions
            HStack {
                Button {
                    query.rootGroup.conditions.append(QueryCondition())
                } label: {
                    Label("Add Condition", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Apply") {
                    onApply()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 500, idealWidth: 600, maxWidth: 800)
        .sheet(isPresented: $showingSaveSheet) {
            SaveQuerySheet(
                query: query,
                typeName: typeName,
                onSave: { showingSaveSheet = false },
                onCancel: { showingSaveSheet = false }
            )
        }
        .sheet(isPresented: $showingHistory) {
            QueryHistoryView(
                typeName: typeName,
                onSelect: { selectedQuery in
                    query = selectedQuery
                    showingHistory = false
                },
                onDismiss: { showingHistory = false }
            )
        }
    }
}

// MARK: - Previews

#Preview("Query Builder - Empty") {
    @Previewable @State var query = ItemQuery()
    QueryBuilderView(
        query: $query,
        availableFields: [
            DiscoveredField(path: "name", name: "name", inferredType: .string, sampleValues: [.string("John"), .string("Jane")], depth: 0),
            DiscoveredField(path: "age", name: "age", inferredType: .number, sampleValues: [.number(25), .number(30)], depth: 0),
            DiscoveredField(path: "isActive", name: "isActive", inferredType: .boolean, sampleValues: [.boolean(true)], depth: 0),
            DiscoveredField(path: "address", name: "address", inferredType: .object, sampleValues: [], depth: 0),
            DiscoveredField(path: "address.city", name: "city", inferredType: .string, sampleValues: [.string("Tokyo")], depth: 1),
        ],
        onApply: {},
        onClear: {}
    )
}

#Preview("Query Builder - With Conditions") {
    @Previewable @State var query = ItemQuery(
        rootGroup: QueryConditionGroup(
            conditions: [
                QueryCondition(fieldPath: "name", operator: .contains, value: .string("test")),
                QueryCondition(fieldPath: "age", operator: .greaterThan, value: .number(18)),
            ]
        )
    )
    QueryBuilderView(
        query: $query,
        availableFields: [
            DiscoveredField(path: "name", name: "name", inferredType: .string, sampleValues: [], depth: 0),
            DiscoveredField(path: "age", name: "age", inferredType: .number, sampleValues: [], depth: 0),
        ],
        onApply: {},
        onClear: {}
    )
}
