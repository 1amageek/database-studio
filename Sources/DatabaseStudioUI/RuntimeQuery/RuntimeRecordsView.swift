import SwiftUI
import DatabaseKit
import DatabaseWire

/// Browses the selected entity through the canonical server query operation.
struct RuntimeRecordsView: View {
    let connection: RuntimeConnection
    let entityName: String
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
        .navigationTitle(entityName)
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
            RuntimeDataOptions(fields: connection.schema?.entities.first(where: { $0.name == entityName })?.fields.map(\.name) ?? [],
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
        let expression: DatabaseKit.Expression?
        do {
            expression = try workspace.filter.expression()
            inputFailure = nil
        } catch {
            inputFailure = error.localizedDescription
            return
        }
        operation?.cancel()
        let request = QueryExecuteOperation.Request(input: .ir(.select(
            SelectQuery(projection: .all, source: .table(TableRef(entityName)),
                        filter: expression,
                        orderBy: workspace.sortField.isEmpty ? nil : [SortKey(.column(ColumnRef(workspace.sortField)),
                            direction: workspace.descending ? .descending : .ascending)]))),
            page: .init(limit: UInt32(workspace.pageLimit)))
        operation = Task { await query.run(request, connection: connection) }
    }

    private func cancel() {
        if query.isRunning { query.cancel() }
        operation?.cancel()
        operation = nil
    }
}
