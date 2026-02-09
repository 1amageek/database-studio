import SwiftUI

/// グラフサイドバー（フィルター + ノード一覧 + アルゴリズム結果）
struct GraphSidebarView: View {
    @Bindable var state: GraphViewState

    var body: some View {
        List(selection: Binding(
            get: { state.selectedNodeID },
            set: { nodeID in
                if let nodeID {
                    state.focusOnNode(nodeID)
                } else {
                    state.selectNode(nil)
                }
            }
        )) {
            // エッジフィルター
            Section {
                ForEach(state.allEdgeLabels, id: \.self) { label in
                    let count = state.edgeCount(for: label)
                    Toggle(isOn: Binding(
                        get: { state.activeEdgeLabels.contains(label) },
                        set: { isOn in
                            if isOn {
                                state.activeEdgeLabels.insert(label)
                            } else {
                                state.activeEdgeLabels.remove(label)
                            }
                            state.zoomToFit()
                        }
                    )) {
                        HStack {
                            Text(label)
                                .lineLimit(1)
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            } header: {
                HStack {
                    Text("Relationships")
                    Spacer()
                    Button("All") {
                        state.activeEdgeLabels = Set(state.allEdgeLabels)
                        state.zoomToFit()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    Button("None") {
                        state.activeEdgeLabels = []
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            // アルゴリズム結果
            algorithmResultsSection(mapping: state.mapping)

            // ノード種別ごとのセクション
            ForEach(filteredNodesByKind, id: \.kind) { kind, nodes in
                Section("\(kind.displayName) (\(nodes.count))") {
                    ForEach(nodes) { node in
                        let style = GraphNodeStyle.style(for: node.kind)
                        Label {
                            Text(node.label)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: style.iconName)
                                .foregroundStyle(style.color)
                        }
                        .tag(node.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $state.searchText, prompt: "Filter nodes")
    }

    // MARK: - フィルター済みノード

    private var filteredNodesByKind: [(kind: GraphNodeKind, nodes: [GraphNode])] {
        if state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return state.visibleNodesByKind
        }
        let query = state.searchText.lowercased()
        return state.visibleNodesByKind.compactMap { kind, nodes in
            let filtered = nodes.filter { $0.label.lowercased().contains(query) }
            guard !filtered.isEmpty else { return nil }
            return (kind, filtered)
        }
    }

    // MARK: - Algorithm Results

    @ViewBuilder
    private func algorithmResultsSection(mapping: GraphVisualMapping) -> some View {
        if mapping.sizeMode == .byPageRank {
            Section("PageRank Top 10") {
                let ranked = state.visibleNodes
                    .filter { ($0.metrics["pageRank"] ?? 0) > 0 }
                    .sorted { ($0.metrics["pageRank"] ?? 0) > ($1.metrics["pageRank"] ?? 0) }
                    .prefix(10)

                ForEach(Array(ranked)) { node in
                    HStack {
                        Text(node.label)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.4f", node.metrics["pageRank"] ?? 0))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .tag(node.id)
                }
            }
        }

        if mapping.colorMode == .byCommunity {
            let communities = Dictionary(grouping: state.visibleNodes.filter { $0.communityID != nil }, by: { $0.communityID! })
            if !communities.isEmpty {
                Section("Communities (\(communities.count))") {
                    ForEach(communities.keys.sorted(), id: \.self) { cid in
                        let count = communities[cid]?.count ?? 0
                        let paletteCount = GraphVisualMapping.communityPalette.count
                        let color = GraphVisualMapping.communityPalette[((cid % paletteCount) + paletteCount) % paletteCount]
                        HStack {
                            Circle()
                                .fill(color)
                                .frame(width: 10, height: 10)
                            Text("Community \(cid)")
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}
