import SwiftUI
import DatabaseKit
import DatabaseWire

/// Browses the selected entity through the canonical server query operation.
struct RuntimeRecordsView: View {
    let connection: RuntimeConnection
    let entityName: String
    @State private var query = RuntimeQuery()
    @State private var sortField = ""
    @State private var descending = false
    @State private var pageLimit = Int(QueryExecuteOperation.Page().limit)
    @State private var operation: Task<Void, Never>?
    @State private var filter = RuntimeRecordFilter()
    @State private var showOptions = false
    @State private var inputFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let inputFailure { Text(inputFailure).foregroundStyle(.red) }
            if let failure = query.failure {
                ContentUnavailableView("Unable to Read Data", systemImage: "exclamationmark.triangle",
                                       description: Text(failure))
            } else if query.wasCancelled {
                ContentUnavailableView("Request Cancelled", systemImage: "stop.circle")
            } else if query.response != nil {
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
                Button("Next Page", systemImage: "chevron.right") {
                    operation = Task { await query.nextPage(connection: connection) }
                }.contentShape(Rectangle()).disabled(!query.hasNextPage || query.isRunning)
            }
        }
        .sheet(isPresented: $showOptions) {
            RuntimeDataOptions(fields: connection.schema?.entities.first(where: { $0.name == entityName })?.fields.map(\.name) ?? [],
                               sortField: sortField, descending: descending, pageLimit: pageLimit, filter: filter) { field, descending, limit, filter in
                self.sortField = field
                self.descending = descending
                self.pageLimit = limit
                self.filter = filter
                showOptions = false
                reload()
            }
        }
        .task { reload() }
        .onDisappear { cancel() }
    }

    private func reload() {
        let expression: DatabaseKit.Expression?
        do {
            expression = try filter.expression()
            inputFailure = nil
        } catch {
            inputFailure = error.localizedDescription
            return
        }
        operation?.cancel()
        let request = QueryExecuteOperation.Request(input: .ir(.select(
            SelectQuery(projection: .all, source: .table(TableRef(entityName)),
                        filter: expression,
                        orderBy: sortField.isEmpty ? nil : [SortKey(.column(ColumnRef(sortField)),
                            direction: descending ? .descending : .ascending)]))),
            page: .init(limit: UInt32(pageLimit)))
        operation = Task { await query.run(request, connection: connection) }
    }

    private func cancel() {
        if query.isRunning { query.cancel() }
        operation?.cancel()
        operation = nil
    }
}
