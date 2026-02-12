import SwiftUI

/// 関連ノード一覧ビュー（Inspector の People / Places タブ）
struct RelatedNodesListView: View {
    let relatedNodes: [(node: GraphNode, role: String)]
    let emptyTitle: String
    let emptyIcon: String
    let emptyDescription: String
    var onSelectNode: (String) -> Void = { _ in }

    var body: some View {
        if relatedNodes.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: emptyIcon,
                description: Text(emptyDescription)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(relatedNodes, id: \.node.id) { entry in
                    nodeRow(entry: entry)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func nodeRow(entry: (node: GraphNode, role: String)) -> some View {
        Button {
            onSelectNode(entry.node.id)
        } label: {
            HStack(spacing: 10) {
                let style = GraphNodeStyle.style(for: entry.node.role)
                Circle()
                    .fill(GraphNodeStyle.color(forClassLabel: primitiveClassLabel(for: entry.node)) ?? style.color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.node.metadata["label"] ?? entry.node.metadata["name"] ?? entry.node.label)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)

                    Text(entry.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func primitiveClassLabel(for node: GraphNode) -> String {
        // ノードの label そのものがプリミティブクラス名かチェック
        if GraphNodeStyle.isPrimitiveClass(node.label) {
            return node.label
        }
        return ""
    }
}
