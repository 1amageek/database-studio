import Foundation

struct GraphSemanticLayer: Identifiable, Sendable {
    let role: GraphNodeRole
    let height: Float
    let lower: SIMD2<Float>
    let upper: SIMD2<Float>
    let count: Int
    var categoryName: String? = nil
    var nodeIDs: Set<String> = []
    var title: String { categoryName ?? role.displayName }
    var id: String { categoryName.map { "category:" + $0 } ?? "role:" + role.rawValue }
    var corners: [SIMD3<Float>] {
        [SIMD3(lower.x, height, lower.y), SIMD3(upper.x, height, lower.y),
         SIMD3(upper.x, height, upper.y), SIMD3(lower.x, height, upper.y)]
    }
}
