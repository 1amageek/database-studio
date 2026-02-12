import SwiftUI

/// ノード種別ごとのスタイル定義
struct GraphNodeStyle {
    let color: Color
    let iconName: String
    let radius: CGFloat

    /// ロールベースのスタイル解決
    static func style(for role: GraphNodeRole) -> GraphNodeStyle {
        switch role {
        case .type:
            return GraphNodeStyle(color: .blue, iconName: "square.stack.3d.up", radius: 30)
        case .instance:
            return GraphNodeStyle(color: .green, iconName: "circle.fill", radius: 26)
        case .property:
            return GraphNodeStyle(color: .orange, iconName: "arrow.right", radius: 22)
        case .literal:
            return GraphNodeStyle(color: .gray, iconName: "quote.closing", radius: 20)
        }
    }

    /// プリミティブクラス名からアイコンを解決
    static func iconName(forClassLabel label: String) -> String? {
        primitiveClassIcons[label]
    }

    /// プリミティブクラス名から色を解決
    static func color(forClassLabel label: String) -> Color? {
        primitiveClassColors[label]
    }

    /// プリミティブクラスかどうか判定
    static func isPrimitiveClass(_ label: String) -> Bool {
        primitiveClassColors[label] != nil
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

    /// プリミティブクラス → 色マッピング
    private static let primitiveClassColors: [String: Color] = [
        "Thing":        Color(.sRGB, red: 0.55, green: 0.55, blue: 0.55, opacity: 1),  // グレー
        "Person":       Color(.sRGB, red: 0.30, green: 0.69, blue: 0.31, opacity: 1),  // グリーン
        "Organization": Color(.sRGB, red: 0.25, green: 0.47, blue: 0.85, opacity: 1),  // ブルー
        "Place":        Color(.sRGB, red: 0.90, green: 0.49, blue: 0.13, opacity: 1),  // オレンジ
        "Event":        Color(.sRGB, red: 0.85, green: 0.26, blue: 0.33, opacity: 1),  // レッド
        "Product":      Color(.sRGB, red: 0.61, green: 0.35, blue: 0.71, opacity: 1),  // パープル
        "Service":      Color(.sRGB, red: 0.00, green: 0.74, blue: 0.83, opacity: 1),  // シアン
        "Technology":   Color(.sRGB, red: 0.13, green: 0.59, blue: 0.95, opacity: 1),  // ライトブルー
        "Industry":     Color(.sRGB, red: 0.47, green: 0.33, blue: 0.28, opacity: 1),  // ブラウン
        "Concept":      Color(.sRGB, red: 0.96, green: 0.76, blue: 0.07, opacity: 1),  // イエロー
        "CreativeWork": Color(.sRGB, red: 0.91, green: 0.44, blue: 0.67, opacity: 1),  // ピンク
        "Facility":     Color(.sRGB, red: 0.40, green: 0.58, blue: 0.42, opacity: 1),  // セージグリーン
        "Market":       Color(.sRGB, red: 0.00, green: 0.59, blue: 0.53, opacity: 1),  // ティール
    ]
}
