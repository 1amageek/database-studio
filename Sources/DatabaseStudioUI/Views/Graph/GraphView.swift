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
        }
        .inspector(isPresented: $showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 250, ideal: 280, max: 350)
        }
        .navigationSubtitle(toolbarSubtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarActions
            }
        }
        .onChange(of: state.selectedNodeID) { _, newValue in
            if newValue != nil {
                showInspector = true
            }
        }
        .onChange(of: GraphWindowState.shared.document?.nodes.count) { _, _ in
            if let newDoc = GraphWindowState.shared.document {
                state.updateDocument(newDoc)
            }
        }
        .onChange(of: GraphWindowState.shared.document?.edges.count) { _, _ in
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
            if let node = state.selectedNode {
                HStack(spacing: 6) {
                    Circle()
                        .fill(GraphNodeStyle.style(for: node.kind).color)
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
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: state.selectedNodeID)
            }
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
                incomingEdges: state.allIncomingEdges(for: node.id),
                outgoingEdges: state.allOutgoingEdges(for: node.id),
                allNodes: state.document.nodes,
                documentEdges: state.document.edges,
                relatedEvents: state.relatedEvents(for: node.id),
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
        let classCount = state.visibleNodes.filter { $0.kind == .owlClass }.count
        let individualCount = state.visibleNodes.filter { $0.kind == .individual }.count
        let edgeCount = state.visibleEdges.count

        var parts = [
            "\(classCount) classes",
            "\(individualCount) individuals",
            "\(edgeCount) edges"
        ]

        if let typeFilter = state.individualTypeFilter,
           let label = state.availableIndividualTypes.first(where: { $0.id == typeFilter })?.label {
            parts.append("Type: \(label)")
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Type Filter Menu

    @ViewBuilder
    private var typeFilterMenu: some View {
        let types = state.availableIndividualTypes
        if !types.isEmpty {
            Menu {
                Button {
                    state.individualTypeFilter = nil
                } label: {
                    if state.individualTypeFilter == nil {
                        Label("All Types", systemImage: "checkmark")
                    } else {
                        Text("All Types")
                    }
                }
                Divider()
                ForEach(types, id: \.id) { type in
                    Button {
                        state.individualTypeFilter = type.id
                    } label: {
                        if state.individualTypeFilter == type.id {
                            Label(type.label, systemImage: "checkmark")
                        } else {
                            Text(type.label)
                        }
                    }
                }
            } label: {
                Image(systemName: state.individualTypeFilter != nil
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
            .help("Filter by Type")
        }
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

        typeFilterMenu

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
