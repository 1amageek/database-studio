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

    /// class ノード同士の追加反発力倍率
    var classRepulsionMultiplier: Double = 4.0

    /// ノード同士の重なりを防ぐ最小距離
    var minimumNodeDistance: Double = 56

    /// 衝突回避力の強さ
    var collisionStrength: Double = 0.7

    /// 度数に応じた理想距離スケール係数（0 = 全エッジ均一長）
    var degreeScaleFactor: Double = 0.3

    /// class ノード ID（外部から設定）
    var classNodeIDs: Set<String> = []

    private(set) var alpha: Double = 1.0
    var alphaDecay: Double = 0.95
    var alphaMin: Double = 0.01
    var velocityDecay: Double = 0.55
    var maxIterations: Int = 300

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
    private var collisionBuckets: [Int64: [Int]] = [:]

    /// Barnes-Hut approximation parameter (theta)
    /// 0.0 = exact N-body, 1.0 = aggressive approximation
    private let theta: Double = 0.8

    // MARK: - 初期化

    func initialize(nodeIDs: [String], size: CGSize, initialPositions: [String: NodePosition]? = nil) {
        positions = [:]
        iteration = 0
        alpha = 1.0
        let centerX = size.width / 2
        let centerY = size.height / 2

        if let initial = initialPositions {
            // 既存位置を引き継ぎ（レイアウト遷移用）
            for id in nodeIDs {
                if let pos = initial[id] {
                    positions[id] = NodePosition(x: pos.x, y: pos.y)
                } else {
                    positions[id] = NodePosition(
                        x: centerX + Double.random(in: -50...50),
                        y: centerY + Double.random(in: -50...50)
                    )
                }
            }
        } else {
            // ノード数に応じて初期配置半径を拡大（密集を防ぐ）
            let baseRadius = min(size.width, size.height) * 0.3
            let radius = baseRadius * sqrt(Double(max(nodeIDs.count, 1)) / 20.0)

            for (i, id) in nodeIDs.enumerated() {
                let angle = (Double(i) / Double(max(nodeIDs.count, 1))) * 2 * .pi
                let jitterX = Double.random(in: -30...30)
                let jitterY = Double.random(in: -30...30)
                positions[id] = NodePosition(
                    x: centerX + cos(angle) * radius + jitterX,
                    y: centerY + sin(angle) * radius + jitterY
                )
            }
        }
    }

    /// 描画前に高速にシミュレーションを進めるウォームアップ
    func warmup(nodeIDs: [String], edges: [GraphEdge], size: CGSize, iterations: Int = 80) {
        for _ in 0..<iterations {
            let running = tick(nodeIDs: nodeIDs, edges: edges, size: size)
            if !running { break }
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
        let nDouble = Double(n)
        let area = max(1.0, Double(size.width * size.height))
        let densitySpacing = sqrt(area / nDouble)
        let baseLength = min(idealLength, max(40.0, densitySpacing * 0.9))
        let maxScaledLength = baseLength * 2.5
        let repulsionScale = min(1.0, sqrt(40.0 / nDouble))
        let scaledRepulsion = repulsionStrength * repulsionScale
        let collisionDistance = max(minimumNodeDistance, baseLength * 0.9)

        // バッファサイズ調整
        if bodyXs.count < n {
            bodyXs = [Double](repeating: 0, count: n)
            bodyYs = [Double](repeating: 0, count: n)
            forcesX = [Double](repeating: 0, count: n)
            forcesY = [Double](repeating: 0, count: n)
        }

        // 位置を並列配列にコピー + 力をリセット
        for i in 0..<n {
            let id = nodeIDs[i]
            if let pos = positions[id], pos.x.isFinite, pos.y.isFinite {
                bodyXs[i] = pos.x
                bodyYs[i] = pos.y
            } else {
                // NaN/inf が入ったノードは中心付近に戻してシミュレーションを継続する
                let fallbackX = centerX + Double.random(in: -20...20)
                let fallbackY = centerY + Double.random(in: -20...20)
                bodyXs[i] = fallbackX
                bodyYs[i] = fallbackY
                positions[id] = NodePosition(x: fallbackX, y: fallbackY)
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
                    repulsionStrength: scaledRepulsion,
                    fx: &forcesX[i], fy: &forcesY[i]
                )
            }
            for i in 0..<n {
                forcesX[i] *= alpha
                forcesY[i] *= alpha
            }
        }

        // Class 同士の追加反発力 O(C²)（C = class ノード数、通常 N より大幅に小さい）
        if !classNodeIDs.isEmpty {
            var classIndices: [Int] = []
            classIndices.reserveCapacity(classNodeIDs.count)
            for i in 0..<n where classNodeIDs.contains(nodeIDs[i]) {
                classIndices.append(i)
            }
            let extraStrength = scaledRepulsion * (classRepulsionMultiplier - 1.0)
            for a in 0..<classIndices.count {
                let ai = classIndices[a]
                for b in (a + 1)..<classIndices.count {
                    let bi = classIndices[b]
                    var dx = bodyXs[bi] - bodyXs[ai]
                    var dy = bodyYs[bi] - bodyYs[ai]
                    var distSq = dx * dx + dy * dy
                    if distSq < 1 {
                        dx = Double.random(in: -1...1)
                        dy = Double.random(in: -1...1)
                        distSq = dx * dx + dy * dy
                    }
                    let dist = sqrt(distSq)
                    let force = extraStrength * alpha / dist
                    let fx = force * dx / dist
                    let fy = force * dy / dist
                    forcesX[ai] -= fx
                    forcesY[ai] -= fy
                    forcesX[bi] += fx
                    forcesY[bi] += fy
                }
            }
        }

        // Spring 引力（エッジ接続ノード間）
        var idToIndex: [String: Int] = [:]
        idToIndex.reserveCapacity(n)
        for i in 0..<n {
            idToIndex[nodeIDs[i]] = i
        }

        // ノード次数を計算（高次数ノードの接続先を遠くに配置するため）
        var degree = [Int](repeating: 0, count: n)
        for edge in edges {
            if let si = idToIndex[edge.sourceID] { degree[si] += 1 }
            if let ti = idToIndex[edge.targetID] { degree[ti] += 1 }
        }

        for edge in edges {
            guard let si = idToIndex[edge.sourceID],
                  let ti = idToIndex[edge.targetID] else { continue }

            let dx = bodyXs[ti] - bodyXs[si]
            let dy = bodyYs[ti] - bodyYs[si]
            let dist = sqrt(dx * dx + dy * dy)
            guard dist > 0 else { continue }

            // 両端の最大次数に応じて理想距離をスケール: sqrt(maxDegree) で緩やかに伸ばす
            let maxDeg = Double(max(degree[si], degree[ti]))
            let scaledLength = min(
                baseLength * (1.0 + degreeScaleFactor * sqrt(maxDeg)),
                maxScaledLength
            )

            let displacement = dist - scaledLength
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

        // 衝突回避（空間ハッシュで近傍のみ評価）
        if n > 1 {
            applyCollisionForces(
                count: n,
                minDistance: collisionDistance,
                strength: collisionStrength
            )
        }

        // 速度・位置更新
        let worldLimit = max(Double(size.width), Double(size.height)) * 8.0
        let minXBound = centerX - worldLimit
        let maxXBound = centerX + worldLimit
        let minYBound = centerY - worldLimit
        let maxYBound = centerY + worldLimit
        let maxVelocity = max(120.0, worldLimit * 0.2)

        for i in 0..<n {
            let id = nodeIDs[i]
            guard var pos = positions[id], !pos.pinned else { continue }

            pos.velocityX = (pos.velocityX + forcesX[i]) * velocityDecay
            pos.velocityY = (pos.velocityY + forcesY[i]) * velocityDecay

            if !pos.velocityX.isFinite { pos.velocityX = 0 }
            if !pos.velocityY.isFinite { pos.velocityY = 0 }
            pos.velocityX = min(max(pos.velocityX, -maxVelocity), maxVelocity)
            pos.velocityY = min(max(pos.velocityY, -maxVelocity), maxVelocity)

            pos.x += pos.velocityX
            pos.y += pos.velocityY
            if !pos.x.isFinite || !pos.y.isFinite {
                pos.x = centerX + Double.random(in: -20...20)
                pos.y = centerY + Double.random(in: -20...20)
                pos.velocityX = 0
                pos.velocityY = 0
            } else {
                pos.x = min(max(pos.x, minXBound), maxXBound)
                pos.y = min(max(pos.y, minYBound), maxYBound)
            }

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

    /// 位置を直接設定（放射レイアウト等で使用）
    func setPositions(_ newPositions: [String: NodePosition]) {
        positions = newPositions
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

    func reheat(alpha targetAlpha: Double = 0.15) {
        for id in positions.keys {
            positions[id]?.velocityX = 0
            positions[id]?.velocityY = 0
        }
        iteration = 0
        alpha = max(targetAlpha, alphaMin * 2)
        isRunning = true
    }

    /// 他レイアウトの位置を既存ノードにマージ（遷移アニメーション用）
    func mergePositions(from other: [String: NodePosition]) {
        for (id, pos) in other {
            guard positions[id] != nil else { continue }
            positions[id]?.x = pos.x
            positions[id]?.y = pos.y
            positions[id]?.velocityX = 0
            positions[id]?.velocityY = 0
        }
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
        thetaSq: Double, repulsionStrength: Double, fx: inout Double, fy: inout Double
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
        if node.nw >= 0 { computeRepulsion(nodeIdx: Int(node.nw), bx: bx, by: by, bodyIndex: bodyIndex, thetaSq: thetaSq, repulsionStrength: repulsionStrength, fx: &fx, fy: &fy) }
        if node.ne >= 0 { computeRepulsion(nodeIdx: Int(node.ne), bx: bx, by: by, bodyIndex: bodyIndex, thetaSq: thetaSq, repulsionStrength: repulsionStrength, fx: &fx, fy: &fy) }
        if node.sw >= 0 { computeRepulsion(nodeIdx: Int(node.sw), bx: bx, by: by, bodyIndex: bodyIndex, thetaSq: thetaSq, repulsionStrength: repulsionStrength, fx: &fx, fy: &fy) }
        if node.se >= 0 { computeRepulsion(nodeIdx: Int(node.se), bx: bx, by: by, bodyIndex: bodyIndex, thetaSq: thetaSq, repulsionStrength: repulsionStrength, fx: &fx, fy: &fy) }
    }

    // MARK: - Collision Avoidance

    private func applyCollisionForces(count n: Int, minDistance: Double, strength: Double) {
        guard minDistance.isFinite, minDistance > 0, strength.isFinite, strength > 0 else { return }

        collisionBuckets.removeAll(keepingCapacity: true)
        collisionBuckets.reserveCapacity(n * 2)

        let minDistSq = minDistance * minDistance

        for i in 0..<n {
            let key = collisionCellKey(x: bodyXs[i], y: bodyYs[i], cellSize: minDistance)
            collisionBuckets[key, default: []].append(i)
        }

        for i in 0..<n {
            let (cellX, cellY) = collisionCell(x: bodyXs[i], y: bodyYs[i], cellSize: minDistance)

            for ox in -1...1 {
                for oy in -1...1 {
                    let neighborKey = collisionPackedKey(
                        x: saturatedAdd(cellX, Int32(ox)),
                        y: saturatedAdd(cellY, Int32(oy))
                    )
                    guard let neighborIndices = collisionBuckets[neighborKey] else { continue }

                    for j in neighborIndices where j > i {
                        var dx = bodyXs[j] - bodyXs[i]
                        var dy = bodyYs[j] - bodyYs[i]
                        var distSq = dx * dx + dy * dy

                        if distSq >= minDistSq { continue }
                        if distSq < 1 {
                            dx = Double.random(in: -1...1)
                            dy = Double.random(in: -1...1)
                            distSq = dx * dx + dy * dy
                        }

                        if distSq <= 0 || !distSq.isFinite { continue }
                        let dist = sqrt(distSq)
                        if dist <= 0 || !dist.isFinite { continue }
                        let penetration = minDistance - dist
                        if penetration <= 0 { continue }

                        let force = penetration * strength
                        if !force.isFinite { continue }
                        let fx = force * dx / dist
                        let fy = force * dy / dist

                        forcesX[i] -= fx
                        forcesY[i] -= fy
                        forcesX[j] += fx
                        forcesY[j] += fy
                    }
                }
            }
        }
    }

    private func collisionCell(x: Double, y: Double, cellSize: Double) -> (x: Int32, y: Int32) {
        guard cellSize.isFinite, cellSize > 0 else { return (0, 0) }
        let scaledX = floor(x / cellSize)
        let scaledY = floor(y / cellSize)
        let cx = clampedInt32(from: scaledX)
        let cy = clampedInt32(from: scaledY)
        return (cx, cy)
    }

    private func collisionCellKey(x: Double, y: Double, cellSize: Double) -> Int64 {
        let cell = collisionCell(x: x, y: y, cellSize: cellSize)
        return collisionPackedKey(x: cell.x, y: cell.y)
    }

    private func collisionPackedKey(x: Int32, y: Int32) -> Int64 {
        (Int64(x) << 32) ^ Int64(UInt32(bitPattern: y))
    }

    private func clampedInt32(from value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        if value <= Double(Int32.min) { return Int32.min }
        if value >= Double(Int32.max) { return Int32.max }
        return Int32(value)
    }

    private func saturatedAdd(_ lhs: Int32, _ rhs: Int32) -> Int32 {
        let sum = Int64(lhs) + Int64(rhs)
        if sum <= Int64(Int32.min) { return Int32.min }
        if sum >= Int64(Int32.max) { return Int32.max }
        return Int32(sum)
    }
}
