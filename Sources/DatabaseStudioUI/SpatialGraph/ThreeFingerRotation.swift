import Foundation

/// Tracks bounded contact positions; a changed contact set starts a new baseline.
@MainActor
struct ThreeFingerRotation {
    private var previous: [AnyHashable: CGPoint] = [:]

    mutating func reset() { previous.removeAll(keepingCapacity: true) }

    mutating func update(_ contacts: [AnyHashable: CGPoint]) -> (translation: CGSize, roll: CGFloat)? {
        guard contacts.count == 3, contacts.values.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            reset()
            return nil
        }
        defer { previous = contacts }
        guard previous.count == 3, contacts.keys.allSatisfy({ previous[$0] != nil }) else { return nil }
        let before = previous.values.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x / 3, y: $0.y + $1.y / 3) }
        let after = contacts.values.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x / 3, y: $0.y + $1.y / 3) }
        var cross: CGFloat = 0
        var dot: CGFloat = 0
        for (id, point) in contacts {
            guard let old = previous[id] else { return nil }
            let x = old.x - before.x, y = old.y - before.y
            let nextX = point.x - after.x, nextY = point.y - after.y
            cross += x * nextY - y * nextX
            dot += x * nextX + y * nextY
        }
        // Screen y points down; positive twist denotes counterclockwise contact rotation.
        let roll = cross == 0 && dot == 0 ? 0 : -atan2(cross, dot)
        return (CGSize(width: after.x - before.x, height: after.y - before.y), roll)
    }
}
