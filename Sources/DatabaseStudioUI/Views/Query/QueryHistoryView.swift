import SwiftUI

/// クエリ履歴ビュー
public struct QueryHistoryView: View {
    let typeName: String
    let onSelect: (ItemQuery) -> Void
    let onDismiss: () -> Void

    @State private var historyService = QueryHistoryService.shared
    @State private var refreshTrigger = false
    @State private var showingDeleteConfirmation = false

    public init(
        typeName: String,
        onSelect: @escaping (ItemQuery) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.typeName = typeName
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    private var filteredQueries: [SavedQuery] {
        historyService.queries(for: typeName)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if filteredQueries.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(filteredQueries) { query in
                            QueryHistoryRow(
                                query: query,
                                onSelect: {
                                    historyService.use(query)
                                    onSelect(query.query)
                                },
                                onDelete: {
                                    historyService.remove(query)
                                    refreshTrigger.toggle()
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved Queries")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                    }
                }

                if !filteredQueries.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 450, minHeight: 350, idealHeight: 450)
        .id(refreshTrigger)
        .alert("Clear All Queries?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                historyService.clearAll()
                refreshTrigger.toggle()
            }
        } message: {
            Text("This will remove all saved queries for \(typeName).")
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No Saved Queries")
                .font(.headline)

            Text("Save a query from the filter builder\nto reuse it later")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Query History Row

private struct QueryHistoryRow: View {
    let query: SavedQuery
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(query.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(query.summary, systemImage: "line.3.horizontal.decrease")
                    Text("•")
                    Text("Used \(query.useCount)x")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onSelect()
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .help("Apply this query")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onSelect()
        }
    }
}

// MARK: - Save Query Sheet

public struct SaveQuerySheet: View {
    let query: ItemQuery
    let typeName: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var queryName: String = ""
    @State private var historyService = QueryHistoryService.shared

    public init(
        query: ItemQuery,
        typeName: String,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.query = query
        self.typeName = typeName
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            Form {
                TextField("Query Name", text: $queryName)

                LabeledContent("Conditions") {
                    Text("\(query.conditionCount) condition(s) for \(typeName)")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Save Query")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = queryName.isEmpty ? "Query \(Date().formatted(date: .abbreviated, time: .shortened))" : queryName
                        historyService.save(name: name, query: query, typeName: typeName)
                        onSave()
                    }
                    .disabled(!query.hasConditions)
                }
            }
        }
        .frame(minWidth: 350, idealWidth: 400, minHeight: 200, idealHeight: 250)
    }
}

// MARK: - Preview

#Preview("Query History") {
    QueryHistoryView(
        typeName: "User",
        onSelect: { query in
            print("Selected: \(query.conditionCount) conditions")
        },
        onDismiss: {
            print("Dismissed")
        }
    )
}

#Preview("Save Query Sheet") {
    SaveQuerySheet(
        query: ItemQuery(rootGroup: QueryConditionGroup(
            conditions: [
                QueryCondition(fieldPath: "name", operator: .contains, value: .string("test"))
            ]
        )),
        typeName: "User",
        onSave: { print("Saved") },
        onCancel: { print("Cancelled") }
    )
}
