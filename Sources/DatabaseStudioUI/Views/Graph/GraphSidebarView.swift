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
            // 選択中のノードフィルタ表示
            if let selectedNode = state.selectedNode {
                Section {
                    HStack {
                        let style = GraphNodeStyle.style(for: selectedNode.kind)
                        let icon = state.nodeIconMap[selectedNode.id] ?? style.iconName
                        let color = state.nodeColorMap[selectedNode.id] ?? style.color
                        Image(systemName: icon)
                            .foregroundStyle(color)
                        Text(selectedNode.label)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            state.selectNode(nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Focused Node")
                }
            }

            // アルゴリズム結果
            algorithmResultsSection(mapping: state.mapping)

            // ノード種別ごとのセクション
            ForEach(filteredNodesByKind, id: \.kind) { kind, nodes in
                Section {
                    ForEach(nodes) { node in
                        let style = GraphNodeStyle.style(for: node.kind)
                        let icon = state.nodeIconMap[node.id] ?? style.iconName
                        let color = state.nodeColorMap[node.id] ?? style.color
                        Label {
                            Text(node.label)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: icon)
                                .foregroundStyle(color)
                        }
                        .tag(node.id)
                    }
                } header: {
                    Text("\(kind.displayName) (\(nodes.count))")
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
            let filtered = nodes.filter { node in
                if node.label.lowercased().contains(query) { return true }
                return node.metadata.values.contains { $0.lowercased().contains(query) }
            }
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
