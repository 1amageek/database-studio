import SwiftUI

/// The scoring metric selected for nearest-neighbor comparisons.
enum VectorComparisonMetric: String, CaseIterable, Identifiable {
    case cosineSimilarity = "Cosine"
    case euclideanDistance = "Euclidean"

    var id: String { rawValue }
}

/// A vector point ranked as a nearest neighbor.
struct NearestNeighborResult: Identifiable {
    let id: String
    let point: VectorPoint
    let score: Float

    var formattedScore: String {
        String(format: "%.4f", score)
    }
}

/// Owns Vector Explorer state and vector interactions.
@Observable @MainActor
final class VectorViewState {

    // MARK: - Document

    var document: VectorDocument {
        didSet { updateProjection() }
    }

    // MARK: - Projection

    private(set) var projectedPoints: [VectorPoint] = []
    private(set) var vectorFailureMessage: String?

    // MARK: - Selection

    var selectedPointID: String? {
        didSet { updateNearestNeighbors() }
    }

    var selectedPoint: VectorPoint? {
        guard let id = selectedPointID else { return nil }
        return pointByIdentifier[id]
    }

    // MARK: - Nearest Neighbors

    var neighborLimit: Int = 5 {
        didSet { updateNearestNeighbors() }
    }
    var comparisonMetric: VectorComparisonMetric = .cosineSimilarity {
        didSet { updateNearestNeighbors() }
    }
    private(set) var nearestNeighbors: [NearestNeighborResult] = [] {
        didSet { nearestNeighborIdentifiers = Set(nearestNeighbors.map(\.id)) }
    }

    private(set) var nearestNeighborIdentifiers: Set<String> = []

    // MARK: - Visual Mapping

    var colorByField: String? {
        didSet { colorAssignments = nil }
    }
    var sizeByField: String?
    var showLabels: Bool = true

    // MARK: - Camera

    var cameraOffset: CGSize = .zero
    var cameraScale: CGFloat = 1.0
    var viewportSize: CGSize = .zero

    // MARK: - Lookup State

    private var pointByIdentifier: [String: VectorPoint] = [:]
    private var colorAssignments: [String: Color]?

    // MARK: - Initialization

    init(document: VectorDocument) {
        self.document = document
        updateProjection()
        if let firstField = document.fieldNames.first(where: { name in
            let uniqueValues = Set(document.points.compactMap { $0.fields[name] })
            return uniqueValues.count >= 2 && uniqueValues.count <= 12
        }) {
            colorByField = firstField
        }
    }

    // MARK: - Projection

    private func updateProjection() {
        do {
            let projectedCoordinates = try PrincipalComponentProjection.project(
                document.points.lazy.map(\.embedding)
            )
            projectedPoints = zip(document.points, projectedCoordinates).map { point, coordinates in
                var projectedPoint = point
                projectedPoint.projected = coordinates
                return projectedPoint
            }
            pointByIdentifier = Dictionary(uniqueKeysWithValues: projectedPoints.map { ($0.id, $0) })
            colorAssignments = nil
            vectorFailureMessage = nil
        } catch {
            projectedPoints = []
            pointByIdentifier = [:]
            colorAssignments = nil
            vectorFailureMessage = error.localizedDescription
        }
    }

    // MARK: - Document Updates

    func updateDocument(_ newDocument: VectorDocument) {
        document = newDocument
    }

    // MARK: - Nearest Neighbors

    private func updateNearestNeighbors() {
        guard let selected = selectedPoint else {
            nearestNeighbors = []
            return
        }

        do {
            var results: [NearestNeighborResult] = []
            results.reserveCapacity(max(document.points.count - 1, 0))

            for point in document.points where point.id != selected.id {
                let score: Float
                switch comparisonMetric {
                case .cosineSimilarity:
                    score = try PrincipalComponentProjection.cosineSimilarity(
                        selected.embedding,
                        point.embedding
                    )
                case .euclideanDistance:
                    let distance = try PrincipalComponentProjection.euclideanDistance(
                        selected.embedding,
                        point.embedding
                    )
                    score = 1 / (1 + distance)
                }
                results.append(NearestNeighborResult(id: point.id, point: point, score: score))
            }

            results.sort { $0.score > $1.score }
            if results.count > neighborLimit {
                results.removeSubrange(neighborLimit..<results.endIndex)
            }
            nearestNeighbors = results
            vectorFailureMessage = nil
        } catch {
            nearestNeighbors = []
            vectorFailureMessage = error.localizedDescription
        }
    }

    // MARK: - Camera

    func zoomToFit(padding: CGFloat = 60) {
        guard !projectedPoints.isEmpty, viewportSize.width > 0, viewportSize.height > 0 else { return }

        let xCoordinates = projectedPoints.map { $0.projected.x }
        let yCoordinates = projectedPoints.map { $0.projected.y }

        guard let minimumX = xCoordinates.min(), let maximumX = xCoordinates.max(),
              let minimumY = yCoordinates.min(), let maximumY = yCoordinates.max() else { return }

        let graphWidth = maximumX - minimumX
        let graphHeight = maximumY - minimumY

        let availableWidth = viewportSize.width - padding * 2
        let availableHeight = viewportSize.height - padding * 2

        let horizontalScale = graphWidth > 0 ? availableWidth / graphWidth : 2
        let verticalScale = graphHeight > 0 ? availableHeight / graphHeight : 2
        cameraScale = min(horizontalScale, verticalScale, 3)

        let centerX = (minimumX + maximumX) / 2
        let centerY = (minimumY + maximumY) / 2

        cameraOffset = CGSize(
            width: viewportSize.width / 2 - centerX * cameraScale,
            height: viewportSize.height / 2 - centerY * cameraScale
        )
    }

    // MARK: - Color Mapping

    func color(for point: VectorPoint) -> Color {
        guard let field = colorByField else { return .blue }

        if colorAssignments == nil {
            updateColorAssignments(for: field)
        }

        guard let value = point.fields[field],
              let color = colorAssignments?[value] else {
            return .gray
        }
        return color
    }

    private func updateColorAssignments(for field: String) {
        let uniqueValues = Set(projectedPoints.compactMap { $0.fields[field] }).sorted()
        let palette: [Color] = [
            .blue, .green, .orange, .purple, .red, .cyan,
            .pink, .yellow, .mint, .indigo, .brown, .teal
        ]
        var assignments: [String: Color] = [:]
        for (colorIndex, value) in uniqueValues.enumerated() {
            assignments[value] = palette[colorIndex % palette.count]
        }
        colorAssignments = assignments
    }

    // MARK: - Size Mapping

    func radius(for point: VectorPoint, base: CGFloat = 5) -> CGFloat {
        guard let field = sizeByField,
              let value = point.fields[field],
              let numericValue = Double(value) else {
            return base
        }
        return base * CGFloat(1 + log2(max(numericValue, 1)) * 0.3)
    }
}
