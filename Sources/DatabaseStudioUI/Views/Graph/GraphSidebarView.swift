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

            // クラスに属さないインスタンス
            untypedInstancesSection

            // クラス・インスタンス以外の種別セクション
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
    }

    // MARK: - クラス階層セクション

    @ViewBuilder
    private var classHierarchySection: some View {
        let tree = state.classTree
        let orphans = state.orphanClassNodes
        // オントロジー階層ツリー
        if !tree.isEmpty {
            Section {
                ForEach(tree) { treeNode in
                    ClassTreeRowView(treeNode: treeNode, state: state)
                }
            } header: {
                Text("Classes (\(state.hierarchyClassCount))")
            }
        }
        // 階層に属さない孤立クラス
        if !orphans.isEmpty {
            Section {
                ForEach(orphans) { treeNode in
                    ClassTreeRowView(treeNode: treeNode, state: state)
                }
            } header: {
                Text("Other Classes (\(orphans.count))")
            }
        }
    }

    // MARK: - 未分類インスタンスセクション

    @ViewBuilder
    private var untypedInstancesSection: some View {
        let typedInstanceIDs = Set(state.nodeTypeMap.keys)
        let instances = state.visibleNodesByRole
            .first(where: { $0.role == .instance })?.nodes ?? []
        let untyped = instances.filter { !typedInstanceIDs.contains($0.id) }
        if !untyped.isEmpty {
            Section {
                ForEach(untyped) { node in
                    nodeRow(node)
                }
            } header: {
                Text("Individuals (\(untyped.count))")
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

    private var nonClassNodesByRole: [(role: GraphNodeRole, nodes: [GraphNode])] {
        // type はクラス階層セクション、instance はクラスツリー内に表示されるため除外
        state.visibleNodesByRole.filter { $0.role != .type && $0.role != .instance }
    }

    // MARK: - Algorithm Results

    @ViewBuilder
    private func algorithmResultsSection(mapping: GraphVisualMapping) -> some View {
        EmptyView()
    }
}

// MARK: - 再帰的クラスツリー行

/// DisclosureGroup を使った再帰的なクラスツリー行
/// OutlineGroup の代わりに明示的な再帰で確実にツリーを表示する
struct ClassTreeRowView: View {
    let treeNode: GraphViewState.ClassTreeNode
    let state: GraphViewState

    var body: some View {
        if treeNode.hasChildren {
            DisclosureGroup {
                if let subclasses = treeNode.subclasses {
                    ForEach(subclasses) { child in
                        ClassTreeRowView(treeNode: child, state: state)
                    }
                }
                if let instances = treeNode.instances {
                    ForEach(instances, id: \.id) { instance in
                        instanceLabel(instance)
                    }
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

    private func instanceLabel(_ node: GraphNode) -> some View {
        let style = GraphNodeStyle.style(for: node.role)
        let color = state.nodeColorMap[node.id] ?? style.color
        return Label {
            Text(node.label)
                .lineLimit(1)
                .font(.callout)
        } icon: {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .tag(node.id)
    }
}
