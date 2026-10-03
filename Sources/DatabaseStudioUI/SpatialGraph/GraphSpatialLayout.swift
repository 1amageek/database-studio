import Foundation
import simd

/// Finite, deterministic coordinates for one admitted relationship network.
struct GraphSpatialLayout: Sendable {
    enum Failure: LocalizedError {
        case capacity, duplicateIdentity, missingEndpoint, invalidPosition, elapsedLimit

        var errorDescription: String? {
            switch self {
            case .capacity: "3D supports up to 1,000 nodes and 4,096 relationships. Load a smaller graph or use 2D."
            case .duplicateIdentity: "The graph contains duplicate node or relationship identities."
            case .missingEndpoint: "A relationship refers to a node outside this graph."
            case .invalidPosition: "The network contains a nonfinite display position."
            case .elapsedLimit: "The network layout exceeded its time budget. Use 2D or load a smaller graph."
            }
        }
    }

    static let maximumNodes = 1000
    static let maximumEdges = 4_096
    static let maximumIterations = 120
    static let maximumRepulsionPairs = 4_000_000

    static func iterationLimit(nodeCount: Int) -> Int {
        guard nodeCount > 1 else { return maximumIterations }
        let pairs = nodeCount * (nodeCount - 1) / 2
        return min(maximumIterations, max(1, maximumRepulsionPairs / pairs))
    }

    static let elapsedLimit: Duration = .seconds(10)
    private(set) var positions: [String: SIMD3<Float>]
    let nodeIDs: [String]

    @concurrent static func compute(document: GraphDocument,
                        initialPositions: [String: SIMD3<Float>] = [:]) async throws -> Self {
        try Task.checkCancellation()
        guard document.nodes.count <= maximumNodes, document.edges.count <= maximumEdges else {
            throw Failure.capacity
        }
        let ids = document.nodes.map(\.id).sorted()
        guard Set(ids).count == ids.count, Set(document.edges.map(\.id)).count == document.edges.count else {
            throw Failure.duplicateIdentity
        }
        let indices = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        let edges = try document.edges.sorted { $0.id < $1.id }.map { edge -> (Int, Int) in
            guard let source = indices[edge.sourceID], let target = indices[edge.targetID] else {
                throw Failure.missingEndpoint
            }
            return (source, target)
        }
        let radius = max(2, pow(Float(ids.count), 1 / 3.0) * 0.8)
        var points = try ids.map { id -> SIMD3<Float> in
            if let point = initialPositions[id] {
                guard finite(point) else { throw Failure.invalidPosition }
                return point
            }
            // Stable bytes, rather than randomized Swift Hasher, seed all three axes.
            var hash: UInt64 = 14_695_981_039_346_656_037
            for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
            hash = (hash ^ (hash >> 30)) &* 0xbf58_476d_1ce4_e5b9
            hash = (hash ^ (hash >> 27)) &* 0x94d0_49bb_1331_11eb
            hash ^= hash >> 31
            return SIMD3(Float(hash & 0xffff), Float((hash >> 16) & 0xffff),
                         Float((hash >> 32) & 0xffff)) / 32_767.5 * radius - SIMD3(repeating: radius)
        }
        var forces = Array(repeating: SIMD3<Float>.zero, count: ids.count)
        var velocities = forces
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: elapsedLimit)
        // ponytail: adapt iterations to bound pair work through 1000 nodes;
        // use a measured spatial tree when larger or more refined layouts are required.
        for iteration in 0..<iterationLimit(nodeCount: ids.count) where !ids.isEmpty {
            try Task.checkCancellation()
            for index in points.indices { forces[index] = -points[index] * 0.002 }
            for first in points.indices {
                for second in (first + 1)..<points.count {
                    var delta = points[second] - points[first]
                    if simd_length_squared(delta) < 0.0001 {
                        delta = SIMD3(Float(first + 1) * 0.001, 0.01, Float(second + 1) * 0.001)
                    }
                    let squared = simd_length_squared(delta)
                    let force = delta * (0.06 / ((squared + 0.15) * sqrt(squared)))
                    forces[first] -= force
                    forces[second] += force
                }
                // A bounded chunk keeps camera, cancellation and window events responsive.
                if first % 32 == 0 {
                    await Task.yield()
                    try Task.checkCancellation()
                    guard clock.now < deadline else { throw Failure.elapsedLimit }
                }
            }
            for (source, target) in edges where source != target {
                let delta = points[target] - points[source]
                let length = max(0.01, simd_length(delta))
                let force = delta * (0.025 * (length - 1.6) / length)
                forces[source] += force
                forces[target] -= force
            }
            var movement: Float = 0
            for index in points.indices {
                var velocity = (velocities[index] + forces[index]) * 0.75
                let speed = simd_length(velocity)
                if speed > 0.2 { velocity *= 0.2 / speed }
                points[index] += velocity
                guard finite(points[index]) else { throw Failure.invalidPosition }
                velocities[index] = velocity
                movement = max(movement, simd_length(velocity))
            }
            if iteration > 20 && movement < 0.001 { break }
        }
        try Task.checkCancellation()
        // Materialize the identity lookup once at the completed layout boundary.
        return Self(positions: Dictionary(uniqueKeysWithValues: zip(ids, points)), nodeIDs: ids)
    }

    static func finite(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }

    mutating func move(_ id: String, to point: SIMD3<Float>) throws {
        guard Self.finite(point) else { throw Failure.invalidPosition }
        guard positions[id] != nil else { throw Failure.missingEndpoint }
        positions[id] = point
    }

    func bounds(for nodes: [GraphNode]) -> (center: SIMD3<Float>, radius: Float) {
        var lower = SIMD3<Float>(repeating: .infinity)
        var upper = SIMD3<Float>(repeating: -.infinity)
        var found = false
        for node in nodes {
            guard let point = positions[node.id] else { continue }
            lower = simd_min(lower, point)
            upper = simd_max(upper, point)
            found = true
        }
        guard found else { return (.zero, 2) }
        return ((lower + upper) / 2, max(2, simd_length(upper - lower) / 2))
    }
}
