import RealityKit
import AppKit
import simd

/// View-owned native geometry and the projected glyphs used by both drawing and picking.
@MainActor
final class GraphSpatialScene {
    struct Glyph {
        let node: GraphNode
        let point: CGPoint
        let depth: Float
        let radius: CGFloat

        var rect: CGRect {
            CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        }

        func contains(_ point: CGPoint) -> Bool {
            let tolerance = max(6, radius)
            if node.role == .type {
                return abs(point.x - self.point.x) <= tolerance && abs(point.y - self.point.y) <= tolerance
            }
            return hypot(point.x - self.point.x, point.y - self.point.y) <= tolerance
        }
    }

    let root = Entity()
    private let camera = PerspectiveCamera()
    private let geometry = Entity()
    private var geometryRevision: UInt64?
    private var geometryAppearance: Bool?
    private var projectionRevision: UInt64?
    private var projectionCamera: GraphSpatialCamera?
    private var projectionSize = CGSize.zero
    private(set) var glyphs: [Glyph] = []
    private(set) var glyphIndices: [String: Int] = [:]
    private(set) var geometryBuildCount = 0
    private(set) var labelPriority: [Int] = []
    var labelBounds: [CGRect] = []

    init() {
        camera.camera.fieldOfViewInDegrees = GraphSpatialCamera.fieldOfView
        root.addChild(camera)
        root.addChild(geometry)
    }

    func update(camera view: GraphSpatialCamera, layout: GraphSpatialLayout, revision: UInt64,
                edges: [GraphEdge], selectedID: String?, dark: Bool) throws {
        camera.look(at: view.target, from: view.eye, relativeTo: nil)
        guard geometryRevision != revision || geometryAppearance != dark else { return }
        var batches: [ModelEntity] = []
        for emphasized in [false, true] {
            // Materialize buffers once per geometry revision at the RealityKit boundary.
            var vertices: [SIMD3<Float>] = []
            var triangles: [UInt32] = []
            vertices.reserveCapacity(edges.count * 8)
            triangles.reserveCapacity(edges.count * 36)
            let faces: [UInt32] = [0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7,
                                   0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5,
                                   2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7]
            for edge in edges {
                guard (selectedID == edge.sourceID || selectedID == edge.targetID) == emphasized,
                      let start = layout.positions[edge.sourceID], let end = layout.positions[edge.targetID] else { continue }
                let delta = end - start
                let length = simd_length(delta)
                guard length > 0.001 else { continue } // Self-relations use screen-space loops.
                let direction = delta / length
                let axis = abs(direction.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
                let right = simd_normalize(simd_cross(direction, axis)) * (emphasized ? 0.008 : 0.004)
                let up = simd_normalize(simd_cross(direction, right)) * (emphasized ? 0.008 : 0.004)
                let base = UInt32(vertices.count) // Admitted graphs have at most 32,768 vertices.
                for point in [start, end] {
                    vertices.append(contentsOf: [point - right - up, point + right - up,
                                                 point + right + up, point - right + up])
                }
                for index in faces { triangles.append(base + index) }
            }
            guard !vertices.isEmpty else { continue }
            var descriptor = MeshDescriptor(name: emphasized ? "Selected relationships" : "Relationships")
            descriptor.positions = MeshBuffers.Positions(vertices)
            descriptor.primitives = .triangles(triangles)
            let mesh = try MeshResource.generate(from: [descriptor])
            var material = UnlitMaterial(color: dark ? .white : .black)
            material.blending = .transparent(opacity: .init(floatLiteral: emphasized ? 0.55 : 0.10))
            batches.append(ModelEntity(mesh: mesh, materials: [material]))
        }
        geometry.children.removeAll()
        for batch in batches { geometry.addChild(batch) }
        geometryRevision = revision
        geometryAppearance = dark
        geometryBuildCount += 1
    }

    func project(camera: GraphSpatialCamera, layout: GraphSpatialLayout, revision: UInt64,
                 nodes: [GraphNode], selectedID: String?, size: CGSize) {
        guard projectionRevision != revision || projectionCamera != camera || projectionSize != size else { return }
        projectionRevision = revision
        projectionCamera = camera
        projectionSize = size
        glyphs.removeAll(keepingCapacity: true)
        glyphIndices.removeAll(keepingCapacity: true)
        for node in nodes {
            guard let position = layout.positions[node.id], let projected = camera.project(position, size: size) else { continue }
            var radius = min(9, max(1.6, 36 / CGFloat(projected.depth) * size.height / 600))
            if node.id == selectedID { radius = max(5.5, radius) }
            // Retain a tolerance around border points; fully offscreen points are not drawn or picked.
            guard CGRect(origin: .zero, size: size).insetBy(dx: -radius, dy: -radius).contains(projected.point) else { continue }
            glyphs.append(Glyph(node: node, point: projected.point, depth: projected.depth, radius: radius))
        }
        glyphs.sort { $0.depth == $1.depth ? $0.node.id < $1.node.id : $0.depth > $1.depth }
        for index in glyphs.indices { glyphIndices[glyphs[index].node.id] = index }
        labelPriority.removeAll(keepingCapacity: true)
        labelPriority.append(contentsOf: glyphs.indices)
        labelPriority.sort {
            let lhs = glyphs[$0], rhs = glyphs[$1]
            if (lhs.node.id == selectedID) != (rhs.node.id == selectedID) { return lhs.node.id == selectedID }
            if lhs.node.isHighlighted != rhs.node.isHighlighted { return lhs.node.isHighlighted }
            return lhs.depth < rhs.depth
        }
    }

    func hit(at point: CGPoint) -> String? {
        glyphs.reversed().first { $0.contains(point) }?.node.id
    }
}
