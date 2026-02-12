import SwiftUI

/// グラフのビジュアルマッピング設定（Gephi Appearance パネル相当）
@Observable @MainActor
final class GraphVisualMapping {

    /// ノードサイズの決定方法
    enum SizeMode: String, CaseIterable {
        case uniform = "Uniform"
        case byPageRank = "PageRank"
        case byDegree = "Degree"
    }

    /// ノードカラーの決定方法
    enum ColorMode: String, CaseIterable {
        case byRole = "Role"
        case byCommunity = "Community"
    }

    var sizeMode: SizeMode = .uniform
    var colorMode: ColorMode = .byRole

    /// 最短経路ハイライト対象ノード ID 列
    var highlightedPath: Set<String> = []

    /// 最短経路ハイライト対象エッジ ID 列
    var highlightedEdges: Set<String> = []

    // MARK: - サイズ計算

    func nodeRadius(for node: GraphNode, baseRadius: CGFloat) -> CGFloat {
        switch sizeMode {
        case .uniform:
            return baseRadius
        case .byPageRank:
            guard let score = node.metrics["pageRank"], score > 0 else { return baseRadius }
            return baseRadius * CGFloat(1.0 + score * 3.0)
        case .byDegree:
            guard let degree = node.metrics["degree"], degree > 0 else { return baseRadius }
            return baseRadius * CGFloat(1.0 + log2(degree + 1) * 0.5)
        }
    }

    // MARK: - カラー計算

    func nodeColor(for node: GraphNode, defaultColor: Color) -> Color {
        switch colorMode {
        case .byRole:
            return defaultColor
        case .byCommunity:
            guard let communityID = node.communityID else { return defaultColor }
            let index = ((communityID % Self.communityPalette.count) + Self.communityPalette.count) % Self.communityPalette.count
            return Self.communityPalette[index]
        }
    }

    /// コミュニティ色パレット（12色）
    static let communityPalette: [Color] = [
        .blue, .green, .orange, .purple, .red, .cyan,
        .pink, .yellow, .mint, .indigo, .brown, .teal
    ]
}
