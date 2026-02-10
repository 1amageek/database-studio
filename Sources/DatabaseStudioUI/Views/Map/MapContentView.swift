import SwiftUI

/// 地図ウィンドウのメインコンテンツ: NavigationSplitView + Inspector + Toolbar
struct MapContentView: View {
    @State private var state: MapViewState
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = false

    init(document: MapDocument) {
        _state = State(initialValue: MapViewState(document: document))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            MapSidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            MapCanvasView(state: state)
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
        .onChange(of: MapWindowState.shared.document?.points.count) { _, _ in
            if let newDoc = MapWindowState.shared.document {
                state.updateDocument(newDoc)
            }
        }
        .onAppear {
            state.zoomToFit()
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        if let point = state.selectedPoint {
            MapInspectorView(
                point: point,
                searchResults: state.searchResults,
                searchMode: state.searchMode
            )
        } else {
            ContentUnavailableView(
                "No Point Selected",
                systemImage: "mappin.slash",
                description: Text("Select a point to see its details")
            )
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarItems: some View {
        Text("\(state.document.points.count) points")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

        Button {
            Task {
                if let refresh = MapWindowState.shared.refreshAction,
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

        // Map Style
        Menu {
            ForEach(MapStyleOption.allCases) { style in
                Button {
                    state.mapStyle = style
                } label: {
                    HStack {
                        Text(style.rawValue)
                        if state.mapStyle == style {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "map")
        }
        .help("Map Style")

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

#Preview("Map View") {
    MapContentView(document: MapPreviewData.document)
        .frame(width: 1100, height: 700)
}
