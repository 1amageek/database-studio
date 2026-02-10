import SwiftUI

/// 距離メトリック
enum VectorMetric: String, CaseIterable, Identifiable {
    case cosine = "Cosine"
    case l2 = "L2"

    var id: String { rawValue }
}

/// KNN 検索結果
struct VectorSearchResult: Identifiable {
    let id: String
    let point: VectorPoint
    let similarity: Float

    var formattedSimilarity: String {
        String(format: "%.4f", similarity)
    }
}

/// Vector Explorer の状態管理
@Observable @MainActor
final class VectorViewState {

    // MARK: - データ

    var document: VectorDocument {
        didSet { reproject() }
    }

    // MARK: - 投影済みポイント

    private(set) var projectedPoints: [VectorPoint] = []

    // MARK: - 選択

    var selectedPointID: String? {
        didSet { computeKNN() }
    }

    var selectedPoint: VectorPoint? {
        guard let id = selectedPointID else { return nil }
        return pointMap[id]
    }

    // MARK: - KNN

    var kValue: Int = 5 {
        didSet { computeKNN() }
    }
    var metric: VectorMetric = .cosine {
        didSet { computeKNN() }
    }
    private(set) var knnResults: [VectorSearchResult] = [] {
        didSet { cachedKNNResultIDs = Set(knnResults.map(\.id)) }
    }

    /// KNN 結果に含まれる ID（キャッシュ済み）
    private(set) var cachedKNNResultIDs: Set<String> = []

    var knnResultIDs: Set<String> { cachedKNNResultIDs }

    // MARK: - ビジュアルマッピング

    var colorByField: String? {
        didSet { colorAssignments = nil }
    }
    var sizeByField: String?
    var showLabels: Bool = true

    // MARK: - カメラ

    var cameraOffset: CGSize = .zero
    var cameraScale: CGFloat = 1.0
    var viewportSize: CGSize = .zero

    // MARK: - キャッシュ

    private var pointMap: [String: VectorPoint] = [:]
    private var colorAssignments: [String: Color]?

    // MARK: - 初期化

    init(document: VectorDocument) {
        self.document = document
        reproject()
        // カテゴリカルフィールドがあれば自動で色分け
        if let firstField = document.fieldNames.first(where: { name in
            let uniqueValues = Set(document.points.compactMap { $0.fields[name] })
            return uniqueValues.count >= 2 && uniqueValues.count <= 12
        }) {
            colorByField = firstField
        }
    }

    // MARK: - 投影

    private func reproject() {
        let embeddings = document.points.map(\.embedding)
        let projected = PCAProjection.project(vectors: embeddings)

        projectedPoints = zip(document.points, projected).map { point, coords in
            var p = point
            p.projected = coords
            return p
        }

        pointMap = Dictionary(uniqueKeysWithValues: projectedPoints.map { ($0.id, $0) })
        colorAssignments = nil
    }

    // MARK: - ドキュメント更新

    func updateDocument(_ newDocument: VectorDocument) {
        document = newDocument
    }

    // MARK: - KNN

    private func computeKNN() {
        guard let selected = selectedPoint else {
            knnResults = []
            return
        }

        let results: [VectorSearchResult] = document.points
            .filter { $0.id != selected.id }
            .map { point in
                let similarity: Float
                switch metric {
                case .cosine:
                    similarity = PCAProjection.cosineSimilarity(selected.embedding, point.embedding)
                case .l2:
                    // L2 を類似度に変換（小さい距離 = 高い類似度）
                    let dist = PCAProjection.l2Distance(selected.embedding, point.embedding)
                    similarity = 1.0 / (1.0 + dist)
                }
                return VectorSearchResult(id: point.id, point: point, similarity: similarity)
            }
            .sorted { $0.similarity > $1.similarity }

        knnResults = Array(results.prefix(kValue))
    }

    // MARK: - カメラ

    func zoomToFit(padding: CGFloat = 60) {
        guard !projectedPoints.isEmpty, viewportSize.width > 0, viewportSize.height > 0 else { return }

        let xs = projectedPoints.map { $0.projected.x }
        let ys = projectedPoints.map { $0.projected.y }

        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!

        let graphWidth = maxX - minX
        let graphHeight = maxY - minY

        let availW = viewportSize.width - padding * 2
        let availH = viewportSize.height - padding * 2

        let scaleX = graphWidth > 0 ? availW / graphWidth : 2.0
        let scaleY = graphHeight > 0 ? availH / graphHeight : 2.0
        cameraScale = min(scaleX, scaleY, 3.0)

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        cameraOffset = CGSize(
            width: viewportSize.width / 2 - centerX * cameraScale,
            height: viewportSize.height / 2 - centerY * cameraScale
        )
    }

    // MARK: - カラーマッピング

    func color(for point: VectorPoint) -> Color {
        guard let field = colorByField else { return .blue }

        if colorAssignments == nil {
            buildColorAssignments(field: field)
        }

        guard let value = point.fields[field],
              let color = colorAssignments?[value] else {
            return .gray
        }
        return color
    }

    private func buildColorAssignments(field: String) {
        let uniqueValues = Set(projectedPoints.compactMap { $0.fields[field] }).sorted()
        let palette: [Color] = [
            .blue, .green, .orange, .purple, .red, .cyan,
            .pink, .yellow, .mint, .indigo, .brown, .teal
        ]
        var assignments: [String: Color] = [:]
        for (i, value) in uniqueValues.enumerated() {
            assignments[value] = palette[i % palette.count]
        }
        colorAssignments = assignments
    }

    // MARK: - サイズマッピング

    func radius(for point: VectorPoint, base: CGFloat = 5) -> CGFloat {
        guard let field = sizeByField,
              let value = point.fields[field],
              let numValue = Double(value) else {
            return base
        }
        return base * CGFloat(1.0 + log2(max(numValue, 1)) * 0.3)
    }
}
