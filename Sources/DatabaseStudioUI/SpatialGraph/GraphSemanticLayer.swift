import Foundation

struct GraphSemanticLayer: Identifiable, Sendable {
    let role: GraphNodeRole
    let height: Float
    let lower: SIMD2<Float>
    let upper: SIMD2<Float>
    let count: Int
    var id: GraphNodeRole { role }
    var corners: [SIMD3<Float>] {
        [SIMD3(lower.x, height, lower.y), SIMD3(upper.x, height, lower.y),
         SIMD3(upper.x, height, upper.y), SIMD3(lower.x, height, upper.y)]
    }
}
