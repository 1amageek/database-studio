import SwiftUI
import DatabaseWire

/// Server-side SQL and SPARQL execution within the connected workspace.
struct RuntimeQueryView: View {
    let connection: RuntimeConnection
    let historyScope: [String]
    @State private var history = RuntimeQueryHistory()
    @State private var historyFailure: String?
    @Bindable var workspace: RuntimeQueryWorkspace
    private var query: RuntimeQuery { workspace.query }
    private var mutation: RuntimeMutation { workspace.mutation }
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if workspace.isMutation {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        if let failure = mutation.failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
                        if let response = mutation.response {
                            ScrollView { Text(String(describing: response)).textSelection(.enabled) }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    editor
                }
            } else {
                RuntimeQueryResultsView(query: query, sourceContent: AnyView(editor))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("Query Options", systemImage: "ellipsis.circle") {
                    Picker("Language", selection: $workspace.language) {
                        Text("SQL").tag(QueryExecuteOperation.Language.sql)
                        Text("SPARQL").tag(QueryExecuteOperation.Language.sparql)
                    }.contentShape(Rectangle())
                    Toggle("Mutation", isOn: $workspace.isMutation)
                        .contentShape(Rectangle()).disabled(query.isRunning || mutation.isRunning)
                    Menu("History") {
                        ForEach(history.entries.filter { $0.scope == historyScope }) { entry in
                            Button(entry.statement) {
                                if let restored = QueryExecuteOperation.Language(rawValue: entry.language) {
                                    workspace.statement = entry.statement
                                    workspace.language = restored
                                }
                            }.contentShape(Rectangle())
                        }
                    }.contentShape(Rectangle())
                    Button("Save") { saveQuery() }.contentShape(Rectangle())
                        .disabled(workspace.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.contentShape(Rectangle()).accessibilityIdentifier("runtime.query.options")
                    if query.isRunning || mutation.isRunning {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { cancel() }.contentShape(Rectangle())
                    } else {
                        Button("Run", systemImage: "play.fill") {
                            saveQuery()
                            task?.cancel()
                            let request = QueryExecuteOperation.Request(
                                input: .text(language: workspace.language, statement: workspace.statement))
                            if workspace.isMutation {
                                let mutationRequest = MutationExecuteOperation.Request(input: .statement(request.input, parameters: []))
                                task = Task { await mutation.execute(mutationRequest, connection: connection) }
                            } else {
                                task = Task { await query.run(request, connection: connection) }
                            }
                        }
                        .contentShape(Rectangle()).keyboardShortcut(.return, modifiers: .command)
                        .disabled(workspace.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
            }
            ToolbarItemGroup(placement: .secondaryAction) {
                Button("Load Remaining", systemImage: "arrow.down.to.line") {
                    task = Task { await query.loadRemainingPages(connection: connection) }
                }.contentShape(Rectangle()).disabled(workspace.isMutation || !query.canCollectRows)
                Button("Next Page", systemImage: "chevron.right") {
                    task = Task { await query.nextPage(connection: connection) }
                }.contentShape(Rectangle()).disabled(workspace.isMutation || !query.hasNextPage || query.isRunning)
            }
        }
        .task {
            do { try history.load() }
            catch { historyFailure = error.localizedDescription }
        }
        .onDisappear { cancel() }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 8) {
                if let historyFailure { Text(historyFailure).foregroundStyle(.red) }
                RuntimeQueryEditor(text: $workspace.statement)
            }.frame(height: 180)
            if let failure = query.failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if query.wasCancelled { Text("Query cancelled").foregroundStyle(.secondary) }
        }
    }

    private func saveQuery() {
        do {
            try history.save(scope: historyScope, language: workspace.language, statement: workspace.statement)
            historyFailure = nil
        } catch { historyFailure = error.localizedDescription }
    }

    private func cancel() {
        if mutation.isRunning { mutation.cancel() }
        if query.isRunning { query.cancel() }
        task?.cancel()
        task = nil
    }
}
