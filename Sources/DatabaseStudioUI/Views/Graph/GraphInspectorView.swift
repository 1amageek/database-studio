import SwiftUI

/// Inspector タブの種別
enum GraphInspectorTab: String, CaseIterable {
    case detail = "Detail"
    case events = "Events"
    case people = "People"
    case places = "Places"
}

/// ノード詳細 Inspector（Detail + Events + People + Places タブ）
struct GraphInspectorView: View {
    let node: GraphNode
    let state: GraphViewState
    let incomingEdges: [GraphEdge]
    let outgoingEdges: [GraphEdge]
    let allNodes: [GraphNode]
    let documentEdges: [GraphEdge]
    let relatedEvents: [(node: GraphNode, date: Date?, role: String)]
    let relatedPeople: [(node: GraphNode, role: String)]
    let relatedPlaces: [(node: GraphNode, role: String)]
    let superclassNodes: [GraphNode]
    let subclassNodes: [GraphNode]
    var onSelectNode: (String) -> Void = { _ in }

    @State private var selectedTab: GraphInspectorTab = .detail

    /// URL として認識するメタデータキー
    private static let urlKeys: Set<String> = ["imageURL", "wikipediaURL", "officialURL"]

    private var imageURL: URL? {
        guard let urlString = node.metadata["imageURL"] else { return nil }
        return URL(string: urlString)
    }

    private var linkEntries: [(key: String, url: URL)] {
        node.metadata
            .filter { Self.urlKeys.contains($0.key) && $0.key != "imageURL" }
            .sorted(by: { $0.key < $1.key })
            .compactMap { key, value in
                guard let url = URL(string: value) else { return nil }
                return (key: key, url: url)
            }
    }

    /// クラス階層チェーン（.type → superclassNodes, .instance → classHierarchyChain）
    private var classHierarchyNodes: [GraphNode]? {
        switch node.role {
        case .type:
            let nodes = superclassNodes
            return nodes.isEmpty ? nil : nodes
        case .instance:
            let chain = state.classHierarchyChain(of: node.id)
            return chain.isEmpty ? nil : chain
        default:
            return nil
        }
    }

    private var regularMetadata: [(key: String, value: String)] {
        node.metadata
            .filter { !Self.urlKeys.contains($0.key) }
            .sorted(by: { $0.key < $1.key })
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $selectedTab) {
                ForEach(GraphInspectorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .detail:
                detailContent
            case .events:
                EventTimelineView(
                    events: relatedEvents,
                    allEdges: documentEdges,
                    allNodes: allNodes,
                    state: state
                )
            case .people:
                RelatedNodesListView(
                    relatedNodes: relatedPeople,
                    emptyTitle: "No People",
                    emptyIcon: "person.slash",
                    emptyDescription: "No people are connected to this node",
                    onSelectNode: onSelectNode
                )
            case .places:
                RelatedNodesListView(
                    relatedNodes: relatedPlaces,
                    emptyTitle: "No Places",
                    emptyIcon: "mappin.slash",
                    emptyDescription: "No places are connected to this node",
                    onSelectNode: onSelectNode
                )
            }
        }
    }

    // MARK: - Detail Tab

    private var detailContent: some View {
        List {
            // Image
            if let imageURL {
                Section {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .failure:
                            Label("Failed to load image", systemImage: "photo.badge.exclamationmark")
                                .foregroundStyle(.secondary)
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                }
            }

            // Info
            Section("Info") {
                LabeledContent("IRI", value: node.id)
                LabeledContent("Label", value: node.label)
                LabeledContent("Role", value: node.role.displayName)
            }

            // Class Hierarchy
            if let hierarchyNodes = classHierarchyNodes, !hierarchyNodes.isEmpty {
                Section("Class Hierarchy") {
                    LabeledContent(node.role == .instance ? "Class" : "Superclass") {
                        HStack(spacing: 4) {
                            ForEach(Array(hierarchyNodes.reversed().enumerated()), id: \.element.id) { index, ancestor in
                                if index > 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)
                                }
                                Button {
                                    onSelectNode(ancestor.id)
                                } label: {
                                    let icon = state.nodeIconMap[ancestor.id] ?? GraphNodeStyle.style(for: ancestor.role).iconName
                                    let color = state.nodeColorMap[ancestor.id] ?? GraphNodeStyle.style(for: ancestor.role).color
                                    HStack(spacing: 3) {
                                        Image(systemName: icon)
                                            .font(.system(size: 10))
                                            .foregroundStyle(color)
                                        Text(ancestor.label)
                                            .font(.callout)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // サブクラス（.type のみ、折りたたみ）
                    if node.role == .type, !subclassNodes.isEmpty {
                        DisclosureGroup("Subclasses (\(subclassNodes.count))") {
                            ForEach(subclassNodes) { child in
                                let icon = state.nodeIconMap[child.id] ?? GraphNodeStyle.style(for: child.role).iconName
                                let color = state.nodeColorMap[child.id] ?? GraphNodeStyle.style(for: child.role).color
                                Button {
                                    onSelectNode(child.id)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: icon)
                                            .font(.system(size: 12))
                                            .foregroundStyle(color)
                                            .frame(width: 18, alignment: .center)
                                        Text(child.label)
                                            .font(.callout)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Links
            if !linkEntries.isEmpty {
                Section("Links") {
                    ForEach(linkEntries, id: \.key) { entry in
                        Link(destination: entry.url) {
                            LabeledContent {
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.secondary)
                            } label: {
                                Text(linkDisplayName(entry.key))
                            }
                        }
                    }
                }
            }

            // Metadata
            if !regularMetadata.isEmpty {
                Section("Metadata") {
                    ForEach(regularMetadata, id: \.key) { key, value in
                        LabeledContent(key, value: value)
                    }
                }
            }

            // Metrics
            if !node.metrics.isEmpty {
                Section("Metrics") {
                    ForEach(node.metrics.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(metricDisplayName(key)) {
                            Text(formatMetric(key: key, value: value))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Degree
            if !outgoingEdges.isEmpty || !incomingEdges.isEmpty {
                Section("Degree") {
                    LabeledContent("In-degree", value: "\(incomingEdges.count)")
                    LabeledContent("Out-degree", value: "\(outgoingEdges.count)")
                    LabeledContent("Total", value: "\(incomingEdges.count + outgoingEdges.count)")
                }
            }

            // Outgoing Edges
            if !outgoingEdges.isEmpty {
                Section("Outgoing (\(outgoingEdges.count))") {
                    ForEach(outgoingEdges) { edge in
                        if let url = URL(string: edge.targetID), url.scheme == "http" || url.scheme == "https" {
                            Link(destination: url) {
                                HStack {
                                    Text(edge.label)
                                        .foregroundStyle(.secondary)
                                        .font(.callout)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                        } else {
                            Button {
                                onSelectNode(edge.targetID)
                            } label: {
                                HStack {
                                    Text(edge.label)
                                        .foregroundStyle(.secondary)
                                        .font(.callout)
                                    Spacer()
                                    Text(nodeLabel(for: edge.targetID))
                                        .lineLimit(1)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Incoming Edges
            if !incomingEdges.isEmpty {
                Section("Incoming (\(incomingEdges.count))") {
                    ForEach(incomingEdges) { edge in
                        if let url = URL(string: edge.sourceID), url.scheme == "http" || url.scheme == "https" {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Spacer()
                                    Text(edge.label)
                                        .foregroundStyle(.secondary)
                                        .font(.callout)
                                }
                            }
                        } else {
                            Button {
                                onSelectNode(edge.sourceID)
                            } label: {
                                HStack {
                                    Text(nodeLabel(for: edge.sourceID))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(edge.label)
                                        .foregroundStyle(.secondary)
                                        .font(.callout)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Helpers

    private func nodeLabel(for id: String) -> String {
        allNodes.first { $0.id == id }?.label ?? localName(id)
    }

    private func metricDisplayName(_ key: String) -> String {
        switch key {
        case "degree": return "Degree"
        case "betweenness": return "Betweenness"
        case "closeness": return "Closeness"
        default: return key
        }
    }

    private func formatMetric(key: String, value: Double) -> String {
        switch key {
        case "degree":
            return "\(Int(value))"
        default:
            return String(format: "%.6f", value)
        }
    }

    private func linkDisplayName(_ key: String) -> String {
        switch key {
        case "wikipediaURL": return "Wikipedia"
        case "officialURL": return "Official Site"
        default: return key
        }
    }
}

