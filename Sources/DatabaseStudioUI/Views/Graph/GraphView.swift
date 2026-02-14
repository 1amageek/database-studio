import SwiftUI

/// RDF グラフとオントロジー構造をフォースレイアウトで可視化する View
public struct GraphView: View {
    @State private var state: GraphViewState
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = false
    private let initialFocusNodeID: String?
    private let initialFocusHops: Int?

    public init(document: GraphDocument, focusNodeID: String? = nil, focusHops: Int? = nil) {
        _state = State(initialValue: GraphViewState(document: document))
        self.initialFocusNodeID = focusNodeID
        self.initialFocusHops = focusHops
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            GraphSidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            detailContent
                .inspector(isPresented: $showInspector) {
                    inspectorContent
                }
        }
        .navigationSubtitle(toolbarSubtitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                navigationActions
            }
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarActions
            }
        }
        .onChange(of: state.selectedNodeID) { _, newValue in
            if newValue != nil {
                showInspector = true
            }
        }
        .onChange(of: graphDocumentFingerprint) { _, _ in
            if let newDoc = GraphWindowState.shared.document {
                state.updateDocument(newDoc)
            }
        }
        .task {
            if let id = initialFocusNodeID {
                if let hops = initialFocusHops {
                    state.focusHops = hops
                }
                state.focusOnNode(id)
            }
        }
    }

    // MARK: - Document Fingerprint

    private var graphDocumentFingerprint: Int? {
        guard let doc = GraphWindowState.shared.document else { return nil }
        let n = doc.nodes.count
        let e = doc.edges.count
        return (n + e) * (n + e + 1) / 2 + e
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if state.showQueryPanel {
            VSplitView {
                canvasWithMinimap
                QueryPanelView(state: state)
                    .frame(minHeight: 100, maxHeight: .infinity)
            }
        } else {
            canvasWithMinimap
        }
    }

    // MARK: - Canvas + Minimap

    private var canvasWithMinimap: some View {
        ZStack(alignment: .bottomTrailing) {
            GraphCanvas(state: state)

            MinimapView(state: state)
                .padding(12)
                .opacity(state.visibleNodes.count > 20 ? 1.0 : 0.0)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                if let node = state.selectedNode {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(GraphNodeStyle.style(for: node.role).color)
                            .frame(width: 8, height: 8)

                        Text(node.label)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)

                        Divider()
                            .frame(height: 16)

                        ForEach(1...5, id: \.self) { hop in
                            Button {
                                state.focusHops = hop
                            } label: {
                                Text("\(hop)")
                                    .font(.caption.weight(state.focusHops == hop ? .bold : .regular).monospacedDigit())
                                    .frame(width: 22, height: 22)
                                    .background(
                                        state.focusHops == hop
                                            ? AnyShapeStyle(Color.accentColor)
                                            : AnyShapeStyle(Color.clear),
                                        in: Circle()
                                    )
                                    .foregroundStyle(state.focusHops == hop ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }

                        Divider()
                            .frame(height: 16)

                        Button {
                            state.selectNode(nil)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !state.filterTokens.isEmpty {
                    GraphFilterBar(state: state)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.2), value: state.selectedNodeID)
            .animation(.easeInOut(duration: 0.2), value: state.filterTokens.count)
        }
        .clipped()
        .frame(minHeight: 200)
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        if let node = state.selectedNode {
            GraphInspectorView(
                node: node,
                state: state,
                incomingEdges: state.allIncomingEdges(for: node.id),
                outgoingEdges: state.allOutgoingEdges(for: node.id),
                allNodes: state.document.nodes,
                documentEdges: state.document.edges,
                relatedEvents: state.relatedEvents(for: node.id),
                relatedPeople: state.relatedNodes(for: node.id, className: "Person"),
                relatedPlaces: state.relatedNodes(for: node.id, className: "Place"),
                superclassNodes: state.superclasses(of: node.id),
                subclassNodes: state.subclasses(of: node.id),
                onSelectNode: { nodeID in
                    state.focusOnNode(nodeID)
                }
            )
        } else {
            ContentUnavailableView(
                "No Node Selected",
                systemImage: "circle.dashed",
                description: Text("Select a node to see its details")
            )
        }
    }

    // MARK: - Toolbar Subtitle

    private var toolbarSubtitle: String {
        if state.isBackboneActive && !state.isFocusMode && !state.isSearchActive {
            let shown = state.visibleNodes.count
            let total = state.document.nodes.count
            let edgeCount = state.visibleEdges.count
            return "\(shown)/\(total) nodes (backbone) · \(edgeCount) edges"
        }

        let classCount = state.visibleNodes.filter { $0.role == .type }.count
        let individualCount = state.visibleNodes.filter { $0.role == .instance }.count
        let edgeCount = state.visibleEdges.count

        var parts: [String] = []
        if classCount > 0 {
            parts.append("\(classCount) classes")
        }
        parts.append("\(individualCount) individuals")
        parts.append("\(edgeCount) edges")

        if !state.filterTokens.isEmpty {
            parts.append("\(state.filterTokens.count) filters")
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Filter Menu

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            Section("Quick Filters") {
                ForEach(GraphFilterPreset.allCases, id: \.label) { preset in
                    Button {
                        state.addPreset(preset)
                    } label: {
                        Label(preset.label, systemImage: preset.systemImage)
                    }
                }
            }

            Divider()

            Section("Add Filter") {
                ForEach(GraphFilterFacetCategory.allCases, id: \.label) { category in
                    Button {
                        state.addFilterToken(for: category)
                    } label: {
                        Label(category.label, systemImage: category.systemImage)
                    }
                }
            }

            if !state.filterTokens.isEmpty {
                Divider()
                Button(role: .destructive) {
                    state.clearAllFilterTokens()
                } label: {
                    Label("Clear All Filters", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: state.filterTokens.isEmpty
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .help("Filters")

    }

    // MARK: - Navigation Actions

    @ViewBuilder
    private var navigationActions: some View {
        Button {
            state.goBack()
        } label: {
            Image(systemName: "chevron.left")
        }
        .help("Back")
        .keyboardShortcut("[", modifiers: .command)
        .disabled(!state.canGoBack)

        Button {
            state.goForward()
        } label: {
            Image(systemName: "chevron.right")
        }
        .help("Forward")
        .keyboardShortcut("]", modifiers: .command)
        .disabled(!state.canGoForward)
    }

    // MARK: - Toolbar Actions

    @ViewBuilder
    private var toolbarActions: some View {
        Button {
            Task {
                if let refresh = GraphWindowState.shared.refreshAction,
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

        if state.isBackboneAvailable {
            Button {
                state.isBackboneActive.toggle()
            } label: {
                Image(systemName: state.isBackboneActive
                      ? "circle.hexagongrid.fill"
                      : "circle.hexagongrid")
            }
            .help(state.isBackboneActive ? "Show All Nodes" : "Show Backbone")
            .keyboardShortcut("b", modifiers: .command)
        }

        Button {
            state.showClassNodes.toggle()
        } label: {
            Image(systemName: state.showClassNodes
                  ? "square.stack.3d.up.fill"
                  : "square.stack.3d.up.slash")
        }
        .help(state.showClassNodes ? "Hide Classes" : "Show Classes")
        .keyboardShortcut("t", modifiers: .command)

        filterMenu

        Menu {
            Section("Node Size") {
                ForEach(GraphVisualMapping.SizeMode.allCases, id: \.self) { mode in
                    Button {
                        state.mapping.sizeMode = mode
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                            if state.mapping.sizeMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Section("Node Color") {
                ForEach(GraphVisualMapping.ColorMode.allCases, id: \.self) { mode in
                    Button {
                        state.mapping.colorMode = mode
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                            if state.mapping.colorMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "paintpalette")
        }
        .help("Appearance")

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                state.showQueryPanel.toggle()
            }
        } label: {
            Image(systemName: "terminal")
        }
        .help("SPARQL Console")
        .keyboardShortcut("c", modifiers: [.command, .shift])

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

#Preview("RDF Graph") {
    GraphView(document: GraphPreviewData.rdfDocument)
        .frame(width: 1100, height: 600)
}

#Preview("Ontology Graph") {
    GraphView(document: GraphPreviewData.ontologyDocument)
        .frame(width: 1100, height: 600)
}
