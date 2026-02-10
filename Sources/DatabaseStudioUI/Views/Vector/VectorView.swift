import SwiftUI

/// Vector Explorer のメインビュー
struct VectorView: View {
    @State private var state: VectorViewState
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = false

    init(document: VectorDocument) {
        _state = State(initialValue: VectorViewState(document: document))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            VectorSidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            VectorCanvas(state: state)
                .inspector(isPresented: $showInspector) {
                    inspectorContent
                        .inspectorColumnWidth(min: 250, ideal: 280, max: 350)
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
        }
        .onChange(of: state.selectedPointID) { _, newValue in
            if newValue != nil {
                showInspector = true
            }
        }
        .onChange(of: VectorWindowState.shared.document?.points.count) { _, _ in
            if let newDoc = VectorWindowState.shared.document {
                state.updateDocument(newDoc)
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        if let point = state.selectedPoint {
            VectorInspectorView(
                point: point,
                knnResults: state.knnResults,
                metric: state.metric
            )
        } else {
            ContentUnavailableView(
                "No Point Selected",
                systemImage: "scope",
                description: Text("Select a point to see its details and nearest neighbors")
            )
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarItems: some View {
        Text("\(state.document.points.count) points, \(state.document.dimensions)D")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

        Button {
            Task {
                if let refresh = VectorWindowState.shared.refreshAction,
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
            state.zoomToFit()
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .help("Zoom to Fit")
        .keyboardShortcut("0", modifiers: .command)

        // Inspector Toggle
        Button {
            showInspector.toggle()
        } label: {
            Image(systemName: "sidebar.trailing")
        }
        .help("Inspector")
        .keyboardShortcut("i", modifiers: [.option, .command])
    }
}

// MARK: - Preview

#Preview("Vector Explorer") {
    VectorView(document: VectorPreviewData.document)
        .frame(width: 1200, height: 800)
}
