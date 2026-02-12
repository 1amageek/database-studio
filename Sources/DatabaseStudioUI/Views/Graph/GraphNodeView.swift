import SwiftUI

/// 個別ノードの View
struct GraphNodeView: View {
    let node: GraphNode
    let isSelected: Bool
    var mapping: GraphVisualMapping?
    var cameraScale: CGFloat = 1.0
    var isSearchMatched: Bool = false
    var isSearchDimmed: Bool = false

    var body: some View {
        let style = GraphNodeStyle.style(for: node.role)
        let radius = mapping?.nodeRadius(for: node, baseRadius: style.radius) ?? style.radius
        let color = mapping?.nodeColor(for: node, defaultColor: style.color) ?? style.color
        let highlighted = node.isHighlighted || (mapping?.highlightedPath.contains(node.id) ?? false)

        ZStack {
            Circle()
                .fill(color.opacity(highlighted ? 0.5 : 0.2))
                .frame(width: radius * 2, height: radius * 2)

            Circle()
                .stroke(
                    isSearchMatched ? Color.yellow : (isSelected ? Color.accentColor : color),
                    lineWidth: isSearchMatched ? 3 : (isSelected ? 3 : (highlighted ? 2.5 : 1.5))
                )
                .frame(width: radius * 2, height: radius * 2)

            Image(systemName: style.iconName)
                .font(.system(size: radius * 0.6))
                .foregroundStyle(color)
        }
        .shadow(
            color: isSearchMatched ? .yellow.opacity(0.7) : (highlighted ? color.opacity(0.6) : (isSelected ? .accentColor.opacity(0.5) : .clear)),
            radius: isSearchMatched ? 10 : (highlighted ? 8 : 6)
        )
        .opacity(isSearchDimmed ? 0.15 : 1.0)
        .overlay(alignment: .bottom) {
            let labelScale = 1.0 / max(cameraScale, 0.15)
            Text(node.label)
                .font(.caption2)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSearchMatched ? .yellow : .primary)
                .scaleEffect(labelScale)
                .offset(y: radius + 8 * labelScale)
                .allowsHitTesting(false)
                .opacity(isSearchDimmed ? 0.15 : 1.0)
        }
    }
}

// MARK: - Preview

#Preview("All Node Roles") {
    HStack(spacing: 40) {
        GraphNodeView(
            node: GraphNode(id: "1", label: "Person", role: .type),
            isSelected: false
        )
        GraphNodeView(
            node: GraphNode(id: "2", label: "Toyota", role: .instance),
            isSelected: true
        )
        GraphNodeView(
            node: GraphNode(id: "3", label: "hasChild", role: .property),
            isSelected: false
        )
        GraphNodeView(
            node: GraphNode(id: "4", label: "Highlighted", role: .instance, isHighlighted: true),
            isSelected: false
        )
        GraphNodeView(
            node: GraphNode(
                id: "5", label: "PageRank High", role: .instance,
                metrics: ["pageRank": 0.85]
            ),
            isSelected: false,
            mapping: {
                let m = GraphVisualMapping()
                m.sizeMode = .byPageRank
                return m
            }()
        )
    }
    .padding(60)
}
