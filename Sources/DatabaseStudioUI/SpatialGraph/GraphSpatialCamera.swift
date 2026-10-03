import Foundation
import simd

/// The camera basis shared by native rendering and screen-space picking.
struct GraphSpatialCamera: Equatable {
    private(set) var orientation: simd_quatf
    var distance: Float = 18
    var target = SIMD3<Float>.zero
    static let fieldOfView: Float = 45

    init(yaw: Float = 0.22, pitch: Float = 0.4, distance: Float = 18, target: SIMD3<Float> = .zero) {
        orientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: -pitch, axis: SIMD3(1, 0, 0))
        self.distance = distance
        self.target = target
    }

    var backward: SIMD3<Float> { orientation.act(SIMD3(0, 0, 1)) }
    var right: SIMD3<Float> { orientation.act(SIMD3(1, 0, 0)) }
    var up: SIMD3<Float> { orientation.act(SIMD3(0, 1, 0)) }
    var eye: SIMD3<Float> { target + backward * distance }

    /// Frame-local constants shared by every point and relationship.
    struct Projection {
        let eye: SIMD3<Float>
        let backward: SIMD3<Float>
        let right: SIMD3<Float>
        let up: SIMD3<Float>
        let size: CGSize
        let focal: Float
        private let near: Float = 0.05

        init(camera: GraphSpatialCamera, size: CGSize) {
            eye = camera.eye
            backward = camera.backward
            right = camera.right
            up = camera.up
            self.size = size
            focal = Float(size.height) / (2 * tan(GraphSpatialCamera.fieldOfView * .pi / 360))
        }

        func project(_ point: SIMD3<Float>) -> (point: CGPoint, depth: Float)? {
            guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite,
                  GraphSpatialLayout.finite(point) else { return nil }
            let relative = point - eye
            let depth = -simd_dot(relative, backward)
            guard depth >= near, depth.isFinite else { return nil }
            return (CGPoint(x: size.width / 2 + CGFloat(simd_dot(relative, right) * focal / depth),
                            y: size.height / 2 - CGFloat(simd_dot(relative, up) * focal / depth)), depth)
        }

        func segment(from start: SIMD3<Float>, to end: SIMD3<Float>) -> (CGPoint, CGPoint)? {
            let firstDepth = -simd_dot(start - eye, backward)
            let lastDepth = -simd_dot(end - eye, backward)
            guard max(firstDepth, lastDepth) >= near else { return nil }
            var first = start, last = end
            // Clip before perspective division; glyph culling must not remove crossing lines.
            let clipDepth = min(Float(0.052), max(firstDepth, lastDepth))
            if firstDepth < near {
                first += (end - start) * ((clipDepth - firstDepth) / (lastDepth - firstDepth))
            } else if lastDepth < near {
                last = start + (end - start) * ((clipDepth - firstDepth) / (lastDepth - firstDepth))
            }
            guard let a = project(first), let b = project(last) else { return nil }
            return (a.point, b.point)
        }
    }

    func project(_ point: SIMD3<Float>, size: CGSize) -> (point: CGPoint, depth: Float)? {
        Projection(camera: self, size: size).project(point)
    }

    func point(onPlaneThrough point: SIMD3<Float>, screen: CGPoint, size: CGSize) -> SIMD3<Float>? {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite,
              screen.x.isFinite, screen.y.isFinite, GraphSpatialLayout.finite(point) else { return nil }
        let focal = Float(size.height) / (2 * tan(Self.fieldOfView * .pi / 360))
        let direction = -backward + right * Float(screen.x - size.width / 2) / focal
            - up * Float(screen.y - size.height / 2) / focal
        let denominator = simd_dot(direction, backward)
        guard abs(denominator) > 0.0001 else { return nil }
        let length = simd_dot(point - eye, backward) / denominator
        let result = eye + direction * length
        guard length > 0, GraphSpatialLayout.finite(result) else { return nil }
        return result
    }

    mutating func orbit(dx: CGFloat, dy: CGFloat, roll: CGFloat = 0) {
        let horizontal = Float(dx) * 0.006, vertical = Float(dy) * 0.006, twist = Float(roll)
        guard horizontal.isFinite, vertical.isFinite, twist.isFinite else { return }
        orientation = simd_normalize(orientation
            * simd_quatf(angle: horizontal, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: -vertical, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: twist, axis: SIMD3(0, 0, 1)))
    }

    /// Makes the displayed network follow physical three-finger movement and twist.
    mutating func rotateNetwork(dx: CGFloat, dy: CGFloat, roll: CGFloat) {
        // Camera yaw and roll oppose content motion; screen-y pitch already follows it.
        orbit(dx: -dx, dy: dy, roll: -roll)
    }

    mutating func zoom(_ delta: CGFloat) { distance = min(500, max(3, distance * Float(exp(-delta)))) }

    mutating func pan(dx: CGFloat, dy: CGFloat, height: CGFloat) {
        guard height > 0 else { return }
        let units = 2 * distance * tan(Self.fieldOfView * .pi / 360) / Float(height)
        target += (-right * Float(dx) + up * Float(dy)) * units
    }

    mutating func fit(center: SIMD3<Float> = .zero, radius: Float, size: CGSize) {
        target = center
        let aspect = Float(max(1, size.width) / max(1, size.height))
        let vertical = Self.fieldOfView * .pi / 360
        let angle = min(vertical, atan(tan(vertical) * aspect))
        distance = max(3, radius / sin(angle) * 1.15)
    }
}
