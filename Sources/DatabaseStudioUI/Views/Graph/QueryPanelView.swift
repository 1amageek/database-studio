import SwiftUI

/// SPARQL クエリエディタ + 結果表示パネル
struct QueryPanelView: View {
    @Bindable var state: GraphViewState

    var body: some View {
        HSplitView {
            // SPARQL エディタ
            VStack(spacing: 0) {
                editorToolbar
                Divider()
                TextEditor(text: $state.queryText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 結果表示
            VStack(spacing: 0) {
                resultToolbar
                Divider()
                resultContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Editor Toolbar

    private var editorToolbar: some View {
        HStack {
            Text("SPARQL")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)

            Spacer()

            Menu {
                Button("SELECT ?s ?p ?o") {
                    state.queryText = "SELECT ?s ?p ?o\nWHERE {\n  ?s ?p ?o\n}\nLIMIT 100"
                }
                Button("SELECT with FILTER") {
                    state.queryText = "SELECT ?s ?p ?o\nWHERE {\n  ?s ?p ?o .\n  FILTER(?p = <predicate>)\n}\nLIMIT 100"
                }
                Button("COUNT triples") {
                    state.queryText = "SELECT (COUNT(*) AS ?count)\nWHERE {\n  ?s ?p ?o\n}"
                }
            } label: {
                Label("Templates", systemImage: "doc.text")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                state.executeQuery()
            } label: {
                Label("Run", systemImage: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(state.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.trailing, 8)
        }
        .frame(height: 28)
        .background(.bar)
    }

    // MARK: - Result Toolbar

    private var resultToolbar: some View {
        HStack {
            Picker("", selection: $state.queryResultMode) {
                Text("Table").tag(QueryResultMode.table)
                Text("Raw").tag(QueryResultMode.raw)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .padding(.leading, 8)

            Spacer()

            if !state.queryResults.isEmpty {
                Text("\(state.queryResults.count) results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.trailing, 8)
            }
        }
        .frame(height: 28)
        .background(.bar)
    }

    // MARK: - Result Content

    @ViewBuilder
    private var resultContent: some View {
        if state.isQueryExecuting {
            ProgressView("Executing...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.queryError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if state.queryResults.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "text.magnifyingglass",
                description: Text("Run a SPARQL query to see results")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch state.queryResultMode {
            case .table:
                queryResultTable
            case .raw:
                queryResultRaw
            }
        }
    }

    // MARK: - Table View

    @ViewBuilder
    private var queryResultTable: some View {
        let columns = state.queryResultColumns
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header
                GridRow {
                    ForEach(columns, id: \.self) { col in
                        Text(col)
                            .font(.system(.caption, design: .monospaced).bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(minWidth: 100, alignment: .leading)
                            .background(.bar)
                    }
                }
                Divider()

                // Rows
                ForEach(state.queryResults) { row in
                    GridRow {
                        ForEach(columns, id: \.self) { col in
                            Text(row.bindings[col] ?? "")
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .frame(minWidth: 100, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Raw View

    private var queryResultRaw: some View {
        ScrollView {
            Text(state.queryResultsRawText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }
}

/// クエリ結果の表示モード
enum QueryResultMode: String, CaseIterable {
    case table = "Table"
    case raw = "Raw"
}

/// SPARQL クエリ結果の1行
struct QueryResultRow: Identifiable {
    let id = UUID()
    var bindings: [String: String]
}
