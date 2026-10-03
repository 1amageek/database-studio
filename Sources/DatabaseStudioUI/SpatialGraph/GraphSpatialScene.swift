import SwiftUI
import simd

/// View-owned endpoint buffers and the perspective paths used by drawing and picking.
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

    private var geometryRevision: UInt64?
    private var projectionRevision: UInt64?
    private var projectionCamera: GraphSpatialCamera?
    private var projectionSize = CGSize.zero
    private var positions: [SIMD3<Float>] = []
    private var indices: [String: Int] = [:]
    private var endpoints: [(source: Int, target: Int, edge: GraphEdge)] = []
    private var projected: [(point: CGPoint, depth: Float)?] = []
    private(set) var glyphs: [Glyph] = []
    private(set) var glyphIndices: [String: Int] = [:]
    private(set) var topologyBuildCount = 0
    private(set) var labelPriority: [Int] = []
    private(set) var normalPath = Path()
    private(set) var emphasizedPath = Path()
    private(set) var arrowPath = Path()
    private(set) var projectedEdgeCount = 0
    private(set) var edgeLabels: [(text: String, point: CGPoint)] = []
    var labelBounds: [CGRect] = []

    func update(layout: GraphSpatialLayout, revision: UInt64, edges: [GraphEdge]) {
        guard geometryRevision != revision else { return }
        positions.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
        endpoints.removeAll(keepingCapacity: true)
        for id in layout.nodeIDs {
            guard let position = layout.positions[id] else { continue }
            indices[id] = positions.count
            positions.append(position)
        }
        for edge in edges {
            guard let source = indices[edge.sourceID], let target = indices[edge.targetID] else { continue }
            endpoints.append((source, target, edge))
        }
        geometryRevision = revision
        topologyBuildCount += 1
    }

    func project(camera: GraphSpatialCamera, layout: GraphSpatialLayout, revision: UInt64,
                 nodes: [GraphNode], selectedID: String?, size: CGSize) {
        guard projectionRevision != revision || projectionCamera != camera || projectionSize != size else { return }
        projectionRevision = revision
        projectionCamera = camera
        projectionSize = size
        let frame = GraphSpatialCamera.Projection(camera: camera, size: size)
        projected.removeAll(keepingCapacity: true)
        for position in positions { projected.append(frame.project(position)) }
        glyphs.removeAll(keepingCapacity: true)
        glyphIndices.removeAll(keepingCapacity: true)
        for node in nodes {
            guard let index = indices[node.id], let point = projected[index] else { continue }
            var radius = min(9, max(1.6, 36 / CGFloat(point.depth) * size.height / 600))
            if node.id == selectedID { radius = max(5.5, radius) }
            guard CGRect(origin: .zero, size: size).insetBy(dx: -radius, dy: -radius).contains(point.point) else { continue }
            glyphs.append(Glyph(node: node, point: point.point, depth: point.depth, radius: radius))
        }
        glyphs.sort { $0.depth == $1.depth ? $0.node.id < $1.node.id : $0.depth > $1.depth }
        for index in glyphs.indices { glyphIndices[glyphs[index].node.id] = index }
        // Reuse depth order; cap candidates, including collision-rejected measurements.
        labelPriority.removeAll(keepingCapacity: true)
        if let selectedID, let index = glyphIndices[selectedID] { labelPriority.append(index) }
        for highlighted in [true, false] {
            for index in glyphs.indices.reversed() where labelPriority.count < 32 {
                let glyph = glyphs[index]
                if glyph.node.id != selectedID && glyph.node.isHighlighted == highlighted
                    && (highlighted || glyph.radius >= 5) { labelPriority.append(index) }
            }
        }
        normalPath = Path(); emphasizedPath = Path(); arrowPath = Path()
        projectedEdgeCount = 0
        edgeLabels.removeAll(keepingCapacity: true)
        for endpoint in endpoints {
            let selected = endpoint.edge.sourceID == selectedID || endpoint.edge.targetID == selectedID
            let start: CGPoint, end: CGPoint
            if let a = projected[endpoint.source], let b = projected[endpoint.target] {
                start = a.point; end = b.point
            } else if let segment = frame.segment(from: positions[endpoint.source], to: positions[endpoint.target]) {
                start = segment.0; end = segment.1
            } else { continue }
            projectedEdgeCount += 1
            func append(to path: inout Path) {
                if endpoint.source == endpoint.target {
                    path.addEllipse(in: CGRect(x: start.x - 12, y: start.y - 23, width: 24, height: 24))
                } else {
                    path.move(to: start); path.addLine(to: end)
                }
            }
            if selected { append(to: &emphasizedPath) } else { append(to: &normalPath) }
            guard selected else { continue }
            let length = hypot(end.x - start.x, end.y - start.y)
            if length > 20, let target = glyphIndices[endpoint.edge.targetID] {
                let ux = (end.x - start.x) / length, uy = (end.y - start.y) / length
                let radius = glyphs[target].radius + 3
                let tip = CGPoint(x: end.x - ux * radius, y: end.y - uy * radius)
                arrowPath.move(to: CGPoint(x: tip.x - ux * 5 - uy * 2, y: tip.y - uy * 5 + ux * 2))
                arrowPath.addLine(to: tip)
                arrowPath.addLine(to: CGPoint(x: tip.x - ux * 5 + uy * 2, y: tip.y - uy * 5 - ux * 2))
            }
            if edgeLabels.count < 32, glyphIndices[endpoint.edge.sourceID] != nil,
               glyphIndices[endpoint.edge.targetID] != nil {
                edgeLabels.append((endpoint.edge.label, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 7)))
            }
        }
    }

    func hit(at point: CGPoint) -> String? {
        glyphs.reversed().first { $0.contains(point) }?.node.id
    }
}
