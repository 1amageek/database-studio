import Foundation

/// インメモリグラフメトリクス計算（FDB 非依存）
///
/// - Degree centrality
/// - PageRank (power iteration)
/// - Community detection (Label Propagation Algorithm)
enum GraphMetricsComputer {

    struct Result: Sendable {
        let degree: [String: Double]
        let pageRank: [String: Double]
        let communityID: [String: Int]
    }

    /// GraphDocument からすべてのメトリクスを一括計算
    static func compute(document: GraphDocument) -> Result {
        let nodes = document.nodes
        let edges = document.edges
        guard !nodes.isEmpty else {
            return Result(degree: [:], pageRank: [:], communityID: [:])
        }

        let nodeIDs = nodes.map(\.id)
        let nodeIDSet = Set(nodeIDs)

        // 隣接リスト構築（全アルゴリズムで共有）
        var outNeighbors: [String: [String]] = [:]
        var inNeighbors: [String: [String]] = [:]
        var undirectedNeighbors: [String: [String]] = [:]

        for id in nodeIDs {
            outNeighbors[id] = []
            inNeighbors[id] = []
            undirectedNeighbors[id] = []
        }

        for edge in edges {
            guard nodeIDSet.contains(edge.sourceID), nodeIDSet.contains(edge.targetID) else { continue }
            outNeighbors[edge.sourceID, default: []].append(edge.targetID)
            inNeighbors[edge.targetID, default: []].append(edge.sourceID)
            undirectedNeighbors[edge.sourceID, default: []].append(edge.targetID)
            undirectedNeighbors[edge.targetID, default: []].append(edge.sourceID)
        }

        let degree = computeDegree(nodeIDs: nodeIDs, outNeighbors: outNeighbors, inNeighbors: inNeighbors)
        let pageRank = computePageRank(nodeIDs: nodeIDs, outNeighbors: outNeighbors, inNeighbors: inNeighbors)
        let communityID = detectCommunities(nodeIDs: nodeIDs, undirectedNeighbors: undirectedNeighbors)

        return Result(degree: degree, pageRank: pageRank, communityID: communityID)
    }

    // MARK: - Degree Centrality

    private static func computeDegree(
        nodeIDs: [String],
        outNeighbors: [String: [String]],
        inNeighbors: [String: [String]]
    ) -> [String: Double] {
        var degree: [String: Double] = [:]
        degree.reserveCapacity(nodeIDs.count)
        for id in nodeIDs {
            let outDeg = outNeighbors[id]?.count ?? 0
            let inDeg = inNeighbors[id]?.count ?? 0
            degree[id] = Double(outDeg + inDeg)
        }
        return degree
    }

    // MARK: - PageRank (Power Iteration)

    private static func computePageRank(
        nodeIDs: [String],
        outNeighbors: [String: [String]],
        inNeighbors: [String: [String]],
        dampingFactor: Double = 0.85,
        maxIterations: Int = 20,
        convergenceThreshold: Double = 1e-6
    ) -> [String: Double] {
        let n = nodeIDs.count
        guard n > 0 else { return [:] }
        let nDouble = Double(n)
        let initial = 1.0 / nDouble

        // 初期スコア
        var score: [String: Double] = [:]
        score.reserveCapacity(n)
        for id in nodeIDs {
            score[id] = initial
        }

        // Dangling ノード（出次数 0）の特定
        let danglingNodes = nodeIDs.filter { (outNeighbors[$0]?.count ?? 0) == 0 }

        // 出次数キャッシュ
        var outDegree: [String: Int] = [:]
        outDegree.reserveCapacity(n)
        for id in nodeIDs {
            outDegree[id] = outNeighbors[id]?.count ?? 0
        }

        for _ in 0..<maxIterations {
            // Dangling sum: 出次数 0 のノードのスコア合計
            var danglingSum = 0.0
            for id in danglingNodes {
                danglingSum += score[id] ?? 0
            }

            var newScore: [String: Double] = [:]
            newScore.reserveCapacity(n)

            let base = (1.0 - dampingFactor) / nDouble + dampingFactor * danglingSum / nDouble

            for id in nodeIDs {
                var s = base
                if let incoming = inNeighbors[id] {
                    for src in incoming {
                        let srcDeg = outDegree[src] ?? 1
                        s += dampingFactor * (score[src] ?? 0) / Double(srcDeg)
                    }
                }
                newScore[id] = s
            }

            // 収束判定（L1 ノルム）
            var delta = 0.0
            for id in nodeIDs {
                delta += abs((newScore[id] ?? 0) - (score[id] ?? 0))
            }

            score = newScore

            if delta < convergenceThreshold {
                break
            }
        }

        return score
    }

    // MARK: - Community Detection (Label Propagation)

    private static func detectCommunities(
        nodeIDs: [String],
        undirectedNeighbors: [String: [String]],
        maxIterations: Int = 20,
        seed: UInt64 = 42
    ) -> [String: Int] {
        let n = nodeIDs.count
        guard n > 0 else { return [:] }

        // 各ノードに初期ラベル割当
        var label: [String: Int] = [:]
        label.reserveCapacity(n)
        for (i, id) in nodeIDs.enumerated() {
            label[id] = i
        }

        var rng = SeededRNG(seed: seed)
        var order = nodeIDs

        for _ in 0..<maxIterations {
            // Fisher-Yates シャッフル（seeded）
            for i in stride(from: order.count - 1, through: 1, by: -1) {
                let j = Int(rng.next() % UInt64(i + 1))
                order.swapAt(i, j)
            }

            var changed = false

            for id in order {
                guard let neighbors = undirectedNeighbors[id], !neighbors.isEmpty else { continue }

                // 近傍ラベルの頻度カウント
                var frequency: [Int: Int] = [:]
                for neighbor in neighbors {
                    if let neighborLabel = label[neighbor] {
                        frequency[neighborLabel, default: 0] += 1
                    }
                }

                // 最頻ラベル（同率の場合は最小ラベル）
                var bestLabel = label[id] ?? 0
                var bestCount = 0
                for (lbl, count) in frequency {
                    if count > bestCount || (count == bestCount && lbl < bestLabel) {
                        bestLabel = lbl
                        bestCount = count
                    }
                }

                if label[id] != bestLabel {
                    label[id] = bestLabel
                    changed = true
                }
            }

            if !changed { break }
        }

        // ラベルを連番正規化（0-based）
        return normalizeLabels(label)
    }

    /// ラベルを初出順で 0-based 連番に正規化
    private static func normalizeLabels(_ labels: [String: Int]) -> [String: Int] {
        var mapping: [Int: Int] = [:]
        var nextID = 0
        var normalized: [String: Int] = [:]
        normalized.reserveCapacity(labels.count)

        // ラベル値でソートして安定した結果を得る
        let sorted = labels.sorted { $0.value < $1.value }
        for (nodeID, rawLabel) in sorted {
            if let mapped = mapping[rawLabel] {
                normalized[nodeID] = mapped
            } else {
                mapping[rawLabel] = nextID
                normalized[nodeID] = nextID
                nextID += 1
            }
        }

        return normalized
    }
}

// MARK: - Seeded Random Number Generator (xorshift128+)

private struct SeededRNG {
    private var state0: UInt64
    private var state1: UInt64

    init(seed: UInt64) {
        state0 = seed == 0 ? 1 : seed
        state1 = seed &* 6364136223846793005 &+ 1442695040888963407
        if state1 == 0 { state1 = 1 }
    }

    mutating func next() -> UInt64 {
        var s1 = state0
        let s0 = state1
        state0 = s0
        s1 ^= s1 << 23
        s1 ^= s1 >> 17
        s1 ^= s0
        s1 ^= s0 >> 26
        state1 = s1
        return state0 &+ state1
    }
}
