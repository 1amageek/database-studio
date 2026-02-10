import SwiftUI

/// ノード種別ごとのスタイル定義
struct GraphNodeStyle {
    let color: Color
    let iconName: String
    let radius: CGFloat

    static func style(for kind: GraphNodeKind) -> GraphNodeStyle {
        switch kind {
        case .owlClass:
            return GraphNodeStyle(color: .blue, iconName: "square.stack.3d.up", radius: 30)
        case .individual:
            return GraphNodeStyle(color: .green, iconName: "circle.fill", radius: 26)
        case .objectProperty:
            return GraphNodeStyle(color: .orange, iconName: "arrow.right", radius: 22)
        case .dataProperty:
            return GraphNodeStyle(color: .purple, iconName: "textformat", radius: 22)
        case .literal:
            return GraphNodeStyle(color: .gray, iconName: "quote.closing", radius: 20)
        }
    }

    /// プリミティブクラス名からアイコンを解決（Individual ノード用）
    /// typeClassLabel は rdf:type で指すクラスのラベル（localName）
    static func iconName(forClassLabel label: String) -> String? {
        primitiveClassIcons[label]
    }

    /// プリミティブクラス → SF Symbol マッピング
    private static let primitiveClassIcons: [String: String] = [
        "Thing":        "cube",
        "Person":       "person.fill",
        "Organization": "building.2.fill",
        "Place":        "mappin.and.ellipse",
        "Event":        "calendar",
        "Product":      "shippingbox.fill",
        "Service":      "wrench.and.screwdriver.fill",
        "Technology":   "cpu",
        "Industry":     "gearshape.2.fill",
        "Concept":      "lightbulb.fill",
        "CreativeWork": "doc.richtext.fill",
        "Facility":     "building.columns.fill",
        "Market":       "chart.line.uptrend.xyaxis",
    ]
}
