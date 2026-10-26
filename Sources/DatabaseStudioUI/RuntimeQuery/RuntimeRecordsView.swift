import SwiftUI
import DatabaseKit
import DatabaseWire

/// Browses the selected SQL relation through the canonical server query operation.
struct RuntimeRecordsView: View {
    let connection: RuntimeConnection
    let relation: RuntimeRelation
    @Bindable var workspace: RuntimeRecordsWorkspace
    private var query: RuntimeQuery { workspace.query }
    @State private var operation: Task<Void, Never>?
    @State private var showOptions = false
    @State private var inputFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let inputFailure { Text(inputFailure).foregroundStyle(.red) }
            if let failure = query.failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if query.wasCancelled { Text("Request Cancelled").foregroundStyle(.secondary) }
            if query.response != nil {
                RuntimeQueryResultsView(query: query)
            } else if !query.isRunning {
                ContentUnavailableView("No Result Yet", systemImage: "tablecells")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(relation.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Data Options", systemImage: "line.3.horizontal.decrease.circle") { showOptions = true }
                    .contentShape(Rectangle()).disabled(query.isRunning)
                    .accessibilityIdentifier("runtime.data.options")
                if query.isRunning {
                    Button("Cancel", systemImage: "stop.fill") { cancel() }.contentShape(Rectangle())
                } else {
                    Button("Refresh", systemImage: "arrow.clockwise") { reload() }.contentShape(Rectangle())
                }
                Button("Load Remaining", systemImage: "arrow.down.to.line") {
                    operation = Task { await query.loadRemainingPages(connection: connection) }
                }.contentShape(Rectangle()).disabled(!query.canCollectRows)
                Button("Next Page", systemImage: "chevron.right") {
                    operation = Task { await query.nextPage(connection: connection) }
                }.contentShape(Rectangle()).disabled(!query.hasNextPage || query.isRunning)
            }
        }
        .sheet(isPresented: $showOptions) {
            RuntimeDataOptions(fields: relation.columns.map(\.name),
                               sortField: workspace.sortField, descending: workspace.descending, pageLimit: workspace.pageLimit, filter: workspace.filter) { field, descending, limit, filter in
                workspace.sortField = field
                workspace.descending = descending
                workspace.pageLimit = limit
                workspace.filter = filter
                showOptions = false
                reload()
            }
        }
        .task { if query.response == nil { reload() } }
        .onDisappear { cancel() }
    }

    private func reload() {
        let request: QueryExecuteOperation.Request
        do {
            request = try workspace.request(for: relation)
            inputFailure = nil
        } catch {
            inputFailure = error.localizedDescription
            return
        }
        operation?.cancel()
        operation = Task { await query.run(request, connection: connection) }
    }

    private func cancel() {
        if query.isRunning { query.cancel() }
        operation?.cancel()
        operation = nil
    }
}
