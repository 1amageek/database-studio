import Foundation
import simd

/// The camera basis shared by native rendering and screen-space picking.
struct GraphSpatialCamera: Equatable {
    var yaw: Float = 0.22
    var pitch: Float = 0.4
    var distance: Float = 18
    var target = SIMD3<Float>.zero
    static let fieldOfView: Float = 45

    var backward: SIMD3<Float> { SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) }
    var right: SIMD3<Float> { simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), backward)) }
    var up: SIMD3<Float> { simd_cross(backward, right) }
    var eye: SIMD3<Float> { target + backward * distance }

    func project(_ point: SIMD3<Float>, size: CGSize) -> (point: CGPoint, depth: Float)? {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite, point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
        let relative = point - eye
        let depth = -simd_dot(relative, backward)
        guard depth > 0.05, depth.isFinite else { return nil }
        let focal = Float(size.height) / (2 * tan(Self.fieldOfView * .pi / 360))
        return (CGPoint(x: size.width / 2 + CGFloat(simd_dot(relative, right) * focal / depth),
                        y: size.height / 2 - CGFloat(simd_dot(relative, up) * focal / depth)), depth)
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

    mutating func orbit(dx: CGFloat, dy: CGFloat) {
        yaw += Float(dx) * 0.006
        pitch = min(1.25, max(0.08, pitch + Float(dy) * 0.006))
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
