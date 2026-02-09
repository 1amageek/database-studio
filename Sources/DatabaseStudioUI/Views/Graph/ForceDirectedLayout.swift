import Foundation

/// ノードの位置と速度
struct NodePosition {
    var x: Double
    var y: Double
    var velocityX: Double = 0
    var velocityY: Double = 0
    var pinned: Bool = false
}

/// Spring ベースのフォースレイアウトシミュレーション（Barnes-Hut O(N log N) 反発力）
///
/// - **Spring 引力**: エッジ接続ノード間に理想距離（idealLength）を持つバネ。
/// - **反発力**: Barnes-Hut quadtree で近似。theta=0.8 で精度と速度のバランスを取る。
/// - **中心引力**: グラフがビュー外に飛ばないよう緩く引き戻す。
/// - **velocity Verlet 風更新**: 温度（alpha）が自然減衰し、滑らかに収束。
///
/// `@Observable` を使用しない。位置変更の通知は `GraphViewState.layoutVersion` で一括制御。
///
/// Reference: Barnes & Hut, "A hierarchical O(N log N) force-calculation algorithm", Nature 1986
@MainActor
final class ForceDirectedLayout {

    // MARK: - パラメータ

    var idealLength: Double = 120
    var springStiffness: Double = 0.04
    var repulsionStrength: Double = 800
    var centerStrength: Double = 0.02

    private(set) var alpha: Double = 1.0
    var alphaDecay: Double = 0.98
    var alphaMin: Double = 0.01
    var velocityDecay: Double = 0.55
    var maxIterations: Int = 500

    // MARK: - 状態

    private(set) var positions: [String: NodePosition] = [:]
    private(set) var iteration: Int = 0
    private(set) var isRunning: Bool = false

    // MARK: - 内部バッファ（フレーム間再利用）

    private var bodyXs: [Double] = []
    private var bodyYs: [Double] = []
    private var forcesX: [Double] = []
    private var forcesY: [Double] = []
    private var qtNodes: [QTNode] = []
    private var qtCount: Int = 0

    /// Barnes-Hut approximation parameter (theta)
    /// 0.0 = exact N-body, 1.0 = aggressive approximation
    private let theta: Double = 0.8

    // MARK: - 初期化

    func initialize(nodeIDs: [String], size: CGSize) {
        positions = [:]
        iteration = 0
        alpha = 1.0
        let centerX = size.width / 2
        let centerY = size.height / 2
        let radius = min(size.width, size.height) * 0.3

        for (i, id) in nodeIDs.enumerated() {
            let angle = (Double(i) / Double(max(nodeIDs.count, 1))) * 2 * .pi
            let jitterX = Double.random(in: -20...20)
            let jitterY = Double.random(in: -20...20)
            positions[id] = NodePosition(
                x: centerX + cos(angle) * radius + jitterX,
                y: centerY + sin(angle) * radius + jitterY
            )
        }
    }

    /// 1ステップ更新。収束時に false を返す。
    @discardableResult
    func tick(nodeIDs: [String], edges: [GraphEdge], size: CGSize) -> Bool {
        guard iteration < maxIterations, alpha > alphaMin else {
            isRunning = false
            return false
        }

        let n = nodeIDs.count
        guard n > 0 else {
            isRunning = false
            return false
        }

        let centerX = size.width / 2
        let centerY = size.height / 2

        // バッファサイズ調整
        if bodyXs.count < n {
            bodyXs = [Double](repeating: 0, count: n)
            bodyYs = [Double](repeating: 0, count: n)
            forcesX = [Double](repeating: 0, count: n)
            forcesY = [Double](repeating: 0, count: n)
        }

        // 位置を並列配列にコピー + 力をリセット
        for i in 0..<n {
            if let pos = positions[nodeIDs[i]] {
                bodyXs[i] = pos.x
                bodyYs[i] = pos.y
            }
            forcesX[i] = 0
            forcesY[i] = 0
        }

        // Barnes-Hut 反発力 O(N log N)
        if n > 1 {
            buildQuadTree(count: n)
            let thetaSq = theta * theta
            for i in 0..<n {
                computeRepulsion(
                    nodeIdx: 0, bx: bodyXs[i], by: bodyYs[i],
                    bodyIndex: i, thetaSq: thetaSq,
                    fx: &forcesX[i], fy: &forcesY[i]
                )
            }
            for i in 0..<n {
                forcesX[i] *= alpha
                forcesY[i] *= alpha
            }
        }

        // Spring 引力（エッジ接続ノード間）
        var idToIndex: [String: Int] = [:]
        idToIndex.reserveCapacity(n)
        for i in 0..<n {
            idToIndex[nodeIDs[i]] = i
        }

        for edge in edges {
            guard let si = idToIndex[edge.sourceID],
                  let ti = idToIndex[edge.targetID] else { continue }

            let dx = bodyXs[ti] - bodyXs[si]
            let dy = bodyYs[ti] - bodyYs[si]
            let dist = sqrt(dx * dx + dy * dy)
            guard dist > 0 else { continue }

            let displacement = dist - idealLength
            let force = springStiffness * displacement * alpha
            let fx = force * dx / dist
            let fy = force * dy / dist

            forcesX[si] += fx
            forcesY[si] += fy
            forcesX[ti] -= fx
            forcesY[ti] -= fy
        }

        // 中心引力
        for i in 0..<n {
            let dx = centerX - bodyXs[i]
            let dy = centerY - bodyYs[i]
            forcesX[i] += dx * centerStrength * alpha
            forcesY[i] += dy * centerStrength * alpha
        }

        // 速度・位置更新
        for i in 0..<n {
            let id = nodeIDs[i]
            guard var pos = positions[id], !pos.pinned else { continue }

            pos.velocityX = (pos.velocityX + forcesX[i]) * velocityDecay
            pos.velocityY = (pos.velocityY + forcesY[i]) * velocityDecay

            pos.x += pos.velocityX
            pos.y += pos.velocityY

            positions[id] = pos
        }

        alpha *= alphaDecay
        iteration += 1
        isRunning = true
        return true
    }

    // MARK: - ノード操作

    func pin(_ nodeID: String, at point: CGPoint) {
        positions[nodeID]?.x = Double(point.x)
        positions[nodeID]?.y = Double(point.y)
        positions[nodeID]?.velocityX = 0
        positions[nodeID]?.velocityY = 0
        positions[nodeID]?.pinned = true
    }

    func unpin(_ nodeID: String) {
        positions[nodeID]?.pinned = false
    }

    func restart() {
        iteration = 0
        alpha = 1.0
        isRunning = true
    }

    func addNodes(_ newNodeIDs: [String]) {
        guard !newNodeIDs.isEmpty else { return }
        let existing = positions.values
        let cx: Double
        let cy: Double
        if existing.isEmpty {
            cx = 400
            cy = 300
        } else {
            cx = existing.map(\.x).reduce(0, +) / Double(existing.count)
            cy = existing.map(\.y).reduce(0, +) / Double(existing.count)
        }
        for id in newNodeIDs where positions[id] == nil {
            positions[id] = NodePosition(
                x: cx + Double.random(in: -80...80),
                y: cy + Double.random(in: -80...80)
            )
        }
    }

    func removeNodes(_ removedNodeIDs: Set<String>) {
        for id in removedNodeIDs {
            positions.removeValue(forKey: id)
        }
    }

    func reheat() {
        for id in positions.keys {
            positions[id]?.velocityX = 0
            positions[id]?.velocityY = 0
        }
        iteration = 0
        alpha = 0.15
        isRunning = true
    }

    // MARK: - Barnes-Hut Quadtree

    /// Flat-array quadtree node（キャッシュフレンドリー）
    private struct QTNode {
        var comX: Double = 0       // center of mass X
        var comY: Double = 0       // center of mass Y
        var mass: Int = 0
        var bodyIndex: Int = -1    // leaf body index (-1 = empty/internal)
        var nw: Int32 = -1         // child indices (-1 = no child)
        var ne: Int32 = -1
        var sw: Int32 = -1
        var se: Int32 = -1
        var minX: Double = 0
        var maxX: Double = 0
        var minY: Double = 0
        var maxY: Double = 0

        var width: Double { maxX - minX }
        var isExternal: Bool { nw < 0 && ne < 0 && sw < 0 && se < 0 }
    }

    private func allocQTNode(minX: Double, maxX: Double, minY: Double, maxY: Double) -> Int {
        let idx = qtCount
        qtCount += 1
        if idx >= qtNodes.count {
            qtNodes.append(QTNode())
        }
        qtNodes[idx] = QTNode(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
        return idx
    }

    private func buildQuadTree(count n: Int) {
        // Compute bounds
        var minX = bodyXs[0], maxX = bodyXs[0]
        var minY = bodyYs[0], maxY = bodyYs[0]
        for i in 1..<n {
            if bodyXs[i] < minX { minX = bodyXs[i] }
            if bodyXs[i] > maxX { maxX = bodyXs[i] }
            if bodyYs[i] < minY { minY = bodyYs[i] }
            if bodyYs[i] > maxY { maxY = bodyYs[i] }
        }
        let pad = max(maxX - minX, maxY - minY, 100) * 0.05 + 1
        minX -= pad; maxX += pad; minY -= pad; maxY += pad

        // Pre-allocate (worst case ~4N nodes)
        let capacity = n * 4 + 16
        if qtNodes.count < capacity {
            qtNodes = [QTNode](repeating: QTNode(), count: capacity)
        }
        qtCount = 0

        let root = allocQTNode(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
        assert(root == 0)

        for i in 0..<n {
            insertBody(i, into: 0, depth: 0)
        }
    }

    private func insertBody(_ bodyIdx: Int, into nodeIdx: Int, depth: Int) {
        let bx = bodyXs[bodyIdx]
        let by = bodyYs[bodyIdx]

        if qtNodes[nodeIdx].mass == 0 {
            // Empty leaf → store body
            qtNodes[nodeIdx].bodyIndex = bodyIdx
            qtNodes[nodeIdx].comX = bx
            qtNodes[nodeIdx].comY = by
            qtNodes[nodeIdx].mass = 1
            return
        }

        // Update center of mass
        let oldMass = Double(qtNodes[nodeIdx].mass)
        let newMass = oldMass + 1
        qtNodes[nodeIdx].comX = (qtNodes[nodeIdx].comX * oldMass + bx) / newMass
        qtNodes[nodeIdx].comY = (qtNodes[nodeIdx].comY * oldMass + by) / newMass
        qtNodes[nodeIdx].mass = Int(newMass)

        // Maximum depth guard: 重なったノードの無限再帰を防止
        guard depth < 20 else { return }

        // Occupied leaf → push existing body into child
        if qtNodes[nodeIdx].bodyIndex >= 0 {
            let existingIdx = qtNodes[nodeIdx].bodyIndex
            qtNodes[nodeIdx].bodyIndex = -1
            insertIntoChild(existingIdx, parentIdx: nodeIdx, depth: depth)
        }

        insertIntoChild(bodyIdx, parentIdx: nodeIdx, depth: depth)
    }

    private func insertIntoChild(_ bodyIdx: Int, parentIdx: Int, depth: Int) {
        let bx = bodyXs[bodyIdx]
        let by = bodyYs[bodyIdx]
        let midX = (qtNodes[parentIdx].minX + qtNodes[parentIdx].maxX) * 0.5
        let midY = (qtNodes[parentIdx].minY + qtNodes[parentIdx].maxY) * 0.5

        let west = bx <= midX
        let north = by <= midY

        if west && north {
            if qtNodes[parentIdx].nw < 0 {
                qtNodes[parentIdx].nw = Int32(allocQTNode(
                    minX: qtNodes[parentIdx].minX, maxX: midX,
                    minY: qtNodes[parentIdx].minY, maxY: midY))
            }
            insertBody(bodyIdx, into: Int(qtNodes[parentIdx].nw), depth: depth + 1)
        } else if !west && north {
            if qtNodes[parentIdx].ne < 0 {
                qtNodes[parentIdx].ne = Int32(allocQTNode(
                    minX: midX, maxX: qtNodes[parentIdx].maxX,
                    minY: qtNodes[parentIdx].minY, maxY: midY))
            }
            insertBody(bodyIdx, into: Int(qtNodes[parentIdx].ne), depth: depth + 1)
        } else if west {
            if qtNodes[parentIdx].sw < 0 {
                qtNodes[parentIdx].sw = Int32(allocQTNode(
                    minX: qtNodes[parentIdx].minX, maxX: midX,
                    minY: midY, maxY: qtNodes[parentIdx].maxY))
            }
            insertBody(bodyIdx, into: Int(qtNodes[parentIdx].sw), depth: depth + 1)
        } else {
            if qtNodes[parentIdx].se < 0 {
                qtNodes[parentIdx].se = Int32(allocQTNode(
                    minX: midX, maxX: qtNodes[parentIdx].maxX,
                    minY: midY, maxY: qtNodes[parentIdx].maxY))
            }
            insertBody(bodyIdx, into: Int(qtNodes[parentIdx].se), depth: depth + 1)
        }
    }

    /// Quadtree を再帰走査して反発力を近似計算
    private func computeRepulsion(
        nodeIdx: Int, bx: Double, by: Double, bodyIndex: Int,
        thetaSq: Double, fx: inout Double, fy: inout Double
    ) {
        let node = qtNodes[nodeIdx]
        guard node.mass > 0 else { return }

        // Self-skip (leaf containing this body)
        if node.mass == 1 && node.bodyIndex == bodyIndex { return }

        var dx = node.comX - bx
        var dy = node.comY - by
        var distSq = dx * dx + dy * dy

        let widthSq = node.width * node.width

        // theta 条件: セルが十分遠ければ一括近似
        if node.isExternal || (widthSq / distSq < thetaSq) {
            if distSq < 1 {
                dx = Double.random(in: -1...1)
                dy = Double.random(in: -1...1)
                distSq = dx * dx + dy * dy
            }
            let dist = sqrt(distSq)
            let force = repulsionStrength * Double(node.mass) / dist
            // body を cluster から押し離す (dx = com - body なので、-dx 方向が離れる方向)
            fx -= force * dx / dist
            fy -= force * dy / dist
            return
        }

        // 子ノードに再帰
        if node.nw >= 0 { computeRepulsion(nodeIdx: Int(node.nw), bx: bx, by: by, bodyIndex: bodyIndex, thetaSq: thetaSq, fx: &fx, fy: &fy) }
        if node.ne >= 0 { computeRepulsion(nodeIdx: Int(node.ne), bx: bx, by: by, bodyIndex: bodyIndex, thetaSq: thetaSq, fx: &fx, fy: &fy) }
        if node.sw >= 0 { computeRepulsion(nodeIdx: Int(node.sw), bx: bx, by: by, bodyIndex: bodyIndex, thetaSq: thetaSq, fx: &fx, fy: &fy) }
        if node.se >= 0 { computeRepulsion(nodeIdx: Int(node.se), bx: bx, by: by, bodyIndex: bodyIndex, thetaSq: thetaSq, fx: &fx, fy: &fy) }
    }
}
