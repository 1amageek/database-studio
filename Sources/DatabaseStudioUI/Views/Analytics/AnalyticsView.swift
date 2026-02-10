import SwiftUI

/// Analytics ダッシュボードのメインビュー
struct AnalyticsView: View {
    @State private var state: AnalyticsViewState
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    init(document: AnalyticsDocument) {
        _state = State(initialValue: AnalyticsViewState(document: document))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            AnalyticsQueryPanel(state: state)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 350)
        } detail: {
            dashboardGrid
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
        }
        .onChange(of: AnalyticsWindowState.shared.document?.items.count) { _, _ in
            if let newDoc = AnalyticsWindowState.shared.document {
                state.updateDocument(newDoc)
            }
        }
    }

    // MARK: - ダッシュボードグリッド

    private var dashboardGrid: some View {
        ScrollView {
            if state.panels.isEmpty {
                ContentUnavailableView(
                    "No Panels",
                    systemImage: "chart.bar",
                    description: Text("Build a query in the sidebar and click 'Add Panel' to create a visualization")
                )
                .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ],
                    spacing: 16
                ) {
                    ForEach(state.panels) { panel in
                        ChartPanelView(panel: panel) {
                            state.removePanel(id: panel.id)
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarItems: some View {
        Text("\(state.document.items.count) items")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

        Button {
            Task {
                if let refresh = AnalyticsWindowState.shared.refreshAction,
                   let newDoc = await refresh() {
                    state.updateDocument(newDoc)
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Refresh")
        .keyboardShortcut("r", modifiers: .command)

        Button {
            state.recalculateAllPanels()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .help("Recalculate All")
    }
}

// MARK: - Preview

#Preview("Analytics Dashboard") {
    AnalyticsView(document: AnalyticsPreviewData.document)
        .frame(width: 1200, height: 800)
}
