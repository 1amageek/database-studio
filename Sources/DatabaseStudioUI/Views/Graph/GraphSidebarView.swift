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
                        let style = GraphNodeStyle.style(for: selectedNode.role)
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

            // クラス階層セクション
            classHierarchySection

            // クラス以外の種別セクション
            ForEach(nonClassNodesByRole, id: \.role) { role, nodes in
                Section {
                    ForEach(nodes) { node in
                        nodeRow(node)
                    }
                } header: {
                    Text("\(role.displayName) (\(nodes.count))")
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $state.searchText, prompt: "Filter nodes")
    }

    // MARK: - クラス階層セクション

    @ViewBuilder
    private var classHierarchySection: some View {
        let totalCount = state.totalClassCount
        if totalCount > 0 {
            if isSearchActive {
                // 検索中はフラットリストで一致するクラスのみ表示
                let query = state.searchText.lowercased()
                let allClassNodes = state.document.nodes
                    .filter { $0.role == .type }
                    .filter { $0.label.lowercased().contains(query) }
                    .sorted { $0.label < $1.label }
                if !allClassNodes.isEmpty {
                    Section {
                        ForEach(allClassNodes) { node in
                            nodeRow(node)
                        }
                    } header: {
                        Text("Classes (\(allClassNodes.count))")
                    }
                }
            } else {
                // 通常時は subClassOf 階層表示（DisclosureGroup による再帰ツリー）
                Section {
                    ForEach(state.classTree) { treeNode in
                        ClassTreeRowView(treeNode: treeNode, state: state)
                    }
                } header: {
                    Text("Classes (\(totalCount))")
                }
            }
        }
    }

    // MARK: - 共通ノード行

    private func nodeRow(_ node: GraphNode) -> some View {
        let style = GraphNodeStyle.style(for: node.role)
        let icon = state.nodeIconMap[node.id] ?? style.iconName
        let color = state.nodeColorMap[node.id] ?? style.color
        return Label {
            Text(node.label)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
        .tag(node.id)
    }

    // MARK: - フィルター

    private var isSearchActive: Bool {
        !state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredNodesByRole: [(role: GraphNodeRole, nodes: [GraphNode])] {
        if !isSearchActive {
            return state.visibleNodesByRole
        }
        let query = state.searchText.lowercased()
        return state.visibleNodesByRole.compactMap { role, nodes in
            let filtered = nodes.filter { node in
                if node.label.lowercased().contains(query) { return true }
                return node.metadata.values.contains { $0.lowercased().contains(query) }
            }
            guard !filtered.isEmpty else { return nil }
            return (role, filtered)
        }
    }

    private var nonClassNodesByRole: [(role: GraphNodeRole, nodes: [GraphNode])] {
        filteredNodesByRole.filter { $0.role != .type }
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

// MARK: - 再帰的クラスツリー行

/// DisclosureGroup を使った再帰的なクラスツリー行
/// OutlineGroup の代わりに明示的な再帰で確実にツリーを表示する
struct ClassTreeRowView: View {
    let treeNode: GraphViewState.ClassTreeNode
    let state: GraphViewState

    var body: some View {
        if let children = treeNode.children {
            DisclosureGroup {
                ForEach(children) { child in
                    ClassTreeRowView(treeNode: child, state: state)
                }
            } label: {
                nodeLabel(treeNode.node)
            }
        } else {
            nodeLabel(treeNode.node)
        }
    }

    private func nodeLabel(_ node: GraphNode) -> some View {
        let style = GraphNodeStyle.style(for: node.role)
        let icon = state.nodeIconMap[node.id] ?? style.iconName
        let color = state.nodeColorMap[node.id] ?? style.color
        return Label {
            Text(node.label)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
        .tag(node.id)
    }
}
