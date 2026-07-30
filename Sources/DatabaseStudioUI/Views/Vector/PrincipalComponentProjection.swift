import Foundation
import Accelerate

/// A deterministic failure while projecting or comparing vectors.
enum PrincipalComponentProjectionError: LocalizedError, Sendable {
    case emptyVector(Int)
    case inconsistentDimension(vectorIndex: Int, expected: Int, actual: Int)
    case nonFiniteValue(vectorIndex: Int, dimensionIndex: Int)
    case comparisonDimensionMismatch(first: Int, second: Int)

    var errorDescription: String? {
        switch self {
        case .emptyVector(let vectorIndex):
            return "Vector \(vectorIndex) has no dimensions"
        case .inconsistentDimension(let vectorIndex, let expected, let actual):
            return "Vector \(vectorIndex) has \(actual) dimensions; expected \(expected)"
        case .nonFiniteValue(let vectorIndex, let dimensionIndex):
            return "Vector \(vectorIndex) contains a non-finite value at dimension \(dimensionIndex)"
        case .comparisonDimensionMismatch(let first, let second):
            return "Cannot compare vectors with \(first) and \(second) dimensions"
        }
    }
}

/// Projects vectors onto their two dominant principal components.
///
/// The implementation keeps one contiguous centered matrix and uses strided
/// Accelerate operations without materializing matrix rows or columns.
enum PrincipalComponentProjection {
    private static let iterationLimit = 100
    private static let convergenceTolerance: Float = 0.000_01

    static func project<Vectors: RandomAccessCollection>(
        _ vectors: Vectors
    ) throws -> [CGPoint] where Vectors.Element == [Float] {
        guard !vectors.isEmpty else { return [] }

        let dimensionCount = vectors[vectors.startIndex].count
        guard dimensionCount > 0 else {
            throw PrincipalComponentProjectionError.emptyVector(0)
        }

        for (vectorIndex, vector) in vectors.enumerated() {
            guard vector.count == dimensionCount else {
                throw PrincipalComponentProjectionError.inconsistentDimension(
                    vectorIndex: vectorIndex,
                    expected: dimensionCount,
                    actual: vector.count
                )
            }
            for (dimensionIndex, value) in vector.enumerated() where !value.isFinite {
                throw PrincipalComponentProjectionError.nonFiniteValue(
                    vectorIndex: vectorIndex,
                    dimensionIndex: dimensionIndex
                )
            }
        }

        if dimensionCount == 1 {
            var points: [CGPoint] = []
            points.reserveCapacity(vectors.count)
            for vector in vectors {
                points.append(CGPoint(x: CGFloat(vector[0]), y: 0))
            }
            return points
        }

        let vectorCount = vectors.count
        var centeredMatrix = [Float](repeating: 0, count: vectorCount * dimensionCount)
        for (vectorIndex, vector) in vectors.enumerated() {
            centeredMatrix.replaceSubrange(
                vectorIndex * dimensionCount..<(vectorIndex + 1) * dimensionCount,
                with: vector
            )
        }

        center(
            matrix: &centeredMatrix,
            vectorCount: vectorCount,
            dimensionCount: dimensionCount
        )

        guard let firstComponent = dominantComponent(
            in: centeredMatrix,
            vectorCount: vectorCount,
            dimensionCount: dimensionCount,
            componentOrdinal: 0,
            orthogonalTo: nil
        ) else {
            // A zero-variance snapshot has one well-defined projected location.
            return [CGPoint](repeating: .zero, count: vectorCount)
        }

        let secondComponent = dominantComponent(
            in: centeredMatrix,
            vectorCount: vectorCount,
            dimensionCount: dimensionCount,
            componentOrdinal: 1,
            orthogonalTo: firstComponent
        )

        return projectedPoints(
            from: centeredMatrix,
            vectorCount: vectorCount,
            dimensionCount: dimensionCount,
            firstComponent: firstComponent,
            secondComponent: secondComponent
        )
    }

    static func cosineSimilarity(_ first: [Float], _ second: [Float]) throws -> Float {
        try validateComparison(first, second)

        var dotProduct: Float = 0
        var firstSquaredMagnitude: Float = 0
        var secondSquaredMagnitude: Float = 0
        vDSP_dotpr(first, 1, second, 1, &dotProduct, vDSP_Length(first.count))
        vDSP_svesq(first, 1, &firstSquaredMagnitude, vDSP_Length(first.count))
        vDSP_svesq(second, 1, &secondSquaredMagnitude, vDSP_Length(second.count))

        let magnitudeProduct = sqrt(firstSquaredMagnitude) * sqrt(secondSquaredMagnitude)
        return magnitudeProduct > 0 ? dotProduct / magnitudeProduct : 0
    }

    static func euclideanDistance(_ first: [Float], _ second: [Float]) throws -> Float {
        try validateComparison(first, second)

        var squaredDistance: Float = 0
        for dimensionIndex in first.indices {
            let difference = first[dimensionIndex] - second[dimensionIndex]
            squaredDistance += difference * difference
        }
        return sqrt(squaredDistance)
    }

    private static func validateComparison(_ first: [Float], _ second: [Float]) throws {
        guard !first.isEmpty else {
            throw PrincipalComponentProjectionError.emptyVector(0)
        }
        guard first.count == second.count else {
            throw PrincipalComponentProjectionError.comparisonDimensionMismatch(
                first: first.count,
                second: second.count
            )
        }

        for (dimensionIndex, value) in first.enumerated() where !value.isFinite {
            throw PrincipalComponentProjectionError.nonFiniteValue(
                vectorIndex: 0,
                dimensionIndex: dimensionIndex
            )
        }
        for (dimensionIndex, value) in second.enumerated() where !value.isFinite {
            throw PrincipalComponentProjectionError.nonFiniteValue(
                vectorIndex: 1,
                dimensionIndex: dimensionIndex
            )
        }
    }

    private static func center(
        matrix: inout [Float],
        vectorCount: Int,
        dimensionCount: Int
    ) {
        var means = [Float](repeating: 0, count: dimensionCount)
        matrix.withUnsafeBufferPointer { matrixBuffer in
            guard let matrixBaseAddress = matrixBuffer.baseAddress else { return }
            for dimensionIndex in 0..<dimensionCount {
                vDSP_meanv(
                    matrixBaseAddress + dimensionIndex,
                    vDSP_Stride(dimensionCount),
                    &means[dimensionIndex],
                    vDSP_Length(vectorCount)
                )
            }
        }

        for vectorIndex in 0..<vectorCount {
            let rowStart = vectorIndex * dimensionCount
            for dimensionIndex in 0..<dimensionCount {
                matrix[rowStart + dimensionIndex] -= means[dimensionIndex]
            }
        }
    }

    private static func dominantComponent(
        in matrix: [Float],
        vectorCount: Int,
        dimensionCount: Int,
        componentOrdinal: Int,
        orthogonalTo previousComponent: [Float]?
    ) -> [Float]? {
        var component = (0..<dimensionCount).map { dimensionIndex in
            let seed = ((dimensionIndex + 1) * (componentOrdinal + 2)) % (dimensionCount + 1)
            return Float(seed + 1) / Float(dimensionCount + 1)
        }

        if let previousComponent {
            orthogonalize(&component, against: previousComponent)
        }
        guard normalize(&component) > 0 else { return nil }

        for _ in 0..<iterationLimit {
            var candidate = covarianceProduct(
                matrix: matrix,
                vectorCount: vectorCount,
                dimensionCount: dimensionCount,
                vector: component
            )
            if let previousComponent {
                orthogonalize(&candidate, against: previousComponent)
            }
            guard normalize(&candidate) > 0 else { return nil }

            let alignment = abs(dotProduct(component, candidate))
            component = candidate
            if 1 - alignment <= convergenceTolerance {
                break
            }
        }

        return component
    }

    private static func covarianceProduct(
        matrix: [Float],
        vectorCount: Int,
        dimensionCount: Int,
        vector: [Float]
    ) -> [Float] {
        var rowProducts = [Float](repeating: 0, count: vectorCount)
        var result = [Float](repeating: 0, count: dimensionCount)

        matrix.withUnsafeBufferPointer { matrixBuffer in
            vector.withUnsafeBufferPointer { vectorBuffer in
                rowProducts.withUnsafeMutableBufferPointer { rowProductsBuffer in
                    guard let matrixBaseAddress = matrixBuffer.baseAddress,
                          let vectorBaseAddress = vectorBuffer.baseAddress,
                          let rowProductsBaseAddress = rowProductsBuffer.baseAddress else {
                        return
                    }

                    for vectorIndex in 0..<vectorCount {
                        vDSP_dotpr(
                            matrixBaseAddress + vectorIndex * dimensionCount,
                            1,
                            vectorBaseAddress,
                            1,
                            rowProductsBaseAddress + vectorIndex,
                            vDSP_Length(dimensionCount)
                        )
                    }
                }
            }

            rowProducts.withUnsafeBufferPointer { rowProductsBuffer in
                result.withUnsafeMutableBufferPointer { resultBuffer in
                    guard let matrixBaseAddress = matrixBuffer.baseAddress,
                          let rowProductsBaseAddress = rowProductsBuffer.baseAddress,
                          let resultBaseAddress = resultBuffer.baseAddress else {
                        return
                    }

                    for dimensionIndex in 0..<dimensionCount {
                        vDSP_dotpr(
                            matrixBaseAddress + dimensionIndex,
                            vDSP_Stride(dimensionCount),
                            rowProductsBaseAddress,
                            1,
                            resultBaseAddress + dimensionIndex,
                            vDSP_Length(vectorCount)
                        )
                    }
                }
            }
        }

        return result
    }

    private static func projectedPoints(
        from matrix: [Float],
        vectorCount: Int,
        dimensionCount: Int,
        firstComponent: [Float],
        secondComponent: [Float]?
    ) -> [CGPoint] {
        var points = [CGPoint](repeating: .zero, count: vectorCount)

        matrix.withUnsafeBufferPointer { matrixBuffer in
            firstComponent.withUnsafeBufferPointer { firstComponentBuffer in
                guard let matrixBaseAddress = matrixBuffer.baseAddress,
                      let firstComponentBaseAddress = firstComponentBuffer.baseAddress else {
                    return
                }

                if let secondComponent {
                    secondComponent.withUnsafeBufferPointer { secondComponentBuffer in
                        guard let secondComponentBaseAddress = secondComponentBuffer.baseAddress else { return }
                        for vectorIndex in 0..<vectorCount {
                            let rowAddress = matrixBaseAddress + vectorIndex * dimensionCount
                            var firstCoordinate: Float = 0
                            var secondCoordinate: Float = 0
                            vDSP_dotpr(
                                rowAddress,
                                1,
                                firstComponentBaseAddress,
                                1,
                                &firstCoordinate,
                                vDSP_Length(dimensionCount)
                            )
                            vDSP_dotpr(
                                rowAddress,
                                1,
                                secondComponentBaseAddress,
                                1,
                                &secondCoordinate,
                                vDSP_Length(dimensionCount)
                            )
                            points[vectorIndex] = CGPoint(
                                x: CGFloat(firstCoordinate),
                                y: CGFloat(secondCoordinate)
                            )
                        }
                    }
                } else {
                    for vectorIndex in 0..<vectorCount {
                        var firstCoordinate: Float = 0
                        vDSP_dotpr(
                            matrixBaseAddress + vectorIndex * dimensionCount,
                            1,
                            firstComponentBaseAddress,
                            1,
                            &firstCoordinate,
                            vDSP_Length(dimensionCount)
                        )
                        points[vectorIndex] = CGPoint(x: CGFloat(firstCoordinate), y: 0)
                    }
                }
            }
        }

        return points
    }

    @discardableResult
    private static func normalize(_ vector: inout [Float]) -> Float {
        var squaredMagnitude: Float = 0
        vDSP_svesq(vector, 1, &squaredMagnitude, vDSP_Length(vector.count))
        let magnitude = sqrt(squaredMagnitude)
        guard magnitude > 0 else { return 0 }

        var inverseMagnitude = 1 / magnitude
        vDSP_vsmul(
            vector,
            1,
            &inverseMagnitude,
            &vector,
            1,
            vDSP_Length(vector.count)
        )
        return magnitude
    }

    private static func orthogonalize(_ vector: inout [Float], against basis: [Float]) {
        var projectionMagnitude = dotProduct(vector, basis)
        projectionMagnitude.negate()
        vDSP_vsma(
            basis,
            1,
            &projectionMagnitude,
            vector,
            1,
            &vector,
            1,
            vDSP_Length(vector.count)
        )
    }

    private static func dotProduct(_ first: [Float], _ second: [Float]) -> Float {
        var result: Float = 0
        vDSP_dotpr(first, 1, second, 1, &result, vDSP_Length(first.count))
        return result
    }
}
