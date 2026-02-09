import SwiftUI

/// ノード種別ごとのスタイル定義
struct GraphNodeStyle {
    let color: Color
    let iconName: String
    let radius: CGFloat

    static func style(for kind: GraphNodeKind) -> GraphNodeStyle {
        switch kind {
        case .owlClass:
            return GraphNodeStyle(color: .blue, iconName: "square.stack.3d.up", radius: 24)
        case .individual:
            return GraphNodeStyle(color: .green, iconName: "circle.fill", radius: 20)
        case .objectProperty:
            return GraphNodeStyle(color: .orange, iconName: "arrow.right", radius: 18)
        case .dataProperty:
            return GraphNodeStyle(color: .purple, iconName: "textformat", radius: 18)
        case .literal:
            return GraphNodeStyle(color: .gray, iconName: "quote.closing", radius: 16)
        }
    }
}
