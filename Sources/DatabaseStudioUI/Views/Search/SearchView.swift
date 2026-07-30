import SwiftUI

/// Search Console のメインビュー
struct SearchView: View {
    @State private var state: SearchViewState
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = false
    @State private var refreshFailureMessage: String?

    init(document: SearchDocument, initialQuery: String = "") {
        _state = State(initialValue: SearchViewState(document: document, initialQuery: initialQuery))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            FacetSidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            resultsList
                .inspector(isPresented: $showInspector) {
                    inspectorContent
                        .inspectorColumnWidth(min: 250, ideal: 280, max: 350)
                }
        }
        .searchable(text: $state.queryText, prompt: "Search...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
        }
        .onChange(of: state.selectedResultID) { _, newValue in
            if newValue != nil {
                showInspector = true
            }
        }
        .onChange(of: SearchWindowState.shared.document?.items.count) { _, _ in
            if let updatedDocument = SearchWindowState.shared.document {
                state.updateDocument(updatedDocument)
            }
        }
        .alert(
            "Unable to Refresh Search Data",
            isPresented: Binding(
                get: { refreshFailureMessage != nil },
                set: { isPresented in
                    if !isPresented { refreshFailureMessage = nil }
                }
            )
        ) {
            Button("OK") { refreshFailureMessage = nil }
        } message: {
            if let refreshFailureMessage {
                Text(refreshFailureMessage)
            }
        }
    }

    // MARK: - 結果リスト

    private var resultsList: some View {
        Group {
            if state.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Enter a Search Query",
                    systemImage: "magnifyingglass",
                    description: Text("\(state.document.items.count) documents indexed")
                )
            } else if state.results.isEmpty {
                ContentUnavailableView.search(text: state.queryText)
            } else {
                VStack(spacing: 0) {
                    // 結果ヘッダー
                    HStack {
                        Text("\(state.results.count) results")
                            .font(.caption.weight(.medium))
                        if state.searchDuration > 0 {
                            Text("in \(String(format: "%.1f ms", state.searchDuration * 1000))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.bar)

                    Divider()

                    List(selection: $state.selectedResultID) {
                        ForEach(state.results) { result in
                            SearchResultRow(
                                result: result,
                                queryTokens: tokenize(state.queryText),
                                isSelected: state.selectedResultID == result.id
                            )
                            .tag(result.id)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        if let result = state.selectedResult {
            SearchInspectorView(result: result)
        } else {
            ContentUnavailableView(
                "No Result Selected",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Select a result to see its details")
            )
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarItems: some View {
        Text("\(state.document.items.count) docs")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

        Button {
            Task {
                do {
                    if let refreshDocument = SearchWindowState.shared.refreshDocument,
                       let refreshedDocument = try await refreshDocument() {
                        state.updateDocument(refreshedDocument)
                    }
                } catch {
                    refreshFailureMessage = error.localizedDescription
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Refresh")
        .keyboardShortcut("r", modifiers: .command)

        // Inspector Toggle
        Button {
            showInspector.toggle()
        } label: {
            Image(systemName: "sidebar.trailing")
        }
        .help("Inspector")
        .keyboardShortcut("i", modifiers: [.option, .command])
    }

    // MARK: - ヘルパー

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count >= 2 }
    }
}

// MARK: - Preview

#Preview("Search Console") {
    SearchView(document: SearchSampleData.document, initialQuery: "machine learning")
        .frame(width: 1100, height: 700)
}
