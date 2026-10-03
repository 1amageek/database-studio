import Foundation

/// Bounded feature-space clustering and a separate two-dimensional PCA projection.
struct GraphFeatureAnalyzer: GraphClusterAnalyzing {
    enum Failure: LocalizedError {
        case invalidConfiguration, invalidGraph, invalidMetric(String), capacity, noFeatures, elapsedLimit, convergenceLimit

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration: "Choose 2–24 clusters and finite feature weights from 0 through 8."
            case .invalidGraph: "The graph has duplicate identities or missing relationship endpoints."
            case .invalidMetric(let key): "The selected metric contains a nonfinite value: \(key)."
            case .capacity: "Feature analysis supports 1,000 nodes, 4,096 relationships and a bounded feature table."
            case .noFeatures: "At least two nodes need informative shared features. Select attributes, relationships or another role."
            case .elapsedLimit: "Feature analysis exceeded its time budget. Reduce the feature set."
            case .convergenceLimit: "Clustering did not converge within its iteration budget. Change the feature selection or cluster count."
            }
        }
    }

    private enum Key: Hashable {
        case type(String), relation(Bool, String, String), attribute(String, String), numeric(String), missing(String)
        var order: [String] {
            switch self {
            case .type(let id): ["type", id]
            case .relation(let incoming, let predicate, let target): ["relation", incoming ? "in" : "out", predicate, target]
            case .attribute(let key, let value): ["attribute", key, value]
            case .numeric(let key): ["numeric", key]
            case .missing(let key): ["missing", key]
            }
        }
    }
    private struct Entry { let column: Int; let value: Double }

    @concurrent func analyze(document: GraphDocument, configuration c: GraphClusterConfiguration) async throws -> GraphClusterResult {
        let clock = ContinuousClock(), deadline = ContinuousClock().now.advanced(by: .seconds(10))
        func checkpoint() throws {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw Failure.elapsedLimit }
        }
        try checkpoint()
        guard (2...24).contains(c.clusterCount), [c.typeWeight, c.relationshipWeight, c.attributeWeight].allSatisfy({ $0.isFinite && (0...8).contains($0) }) else { throw Failure.invalidConfiguration }
        guard document.nodes.count <= 1000, document.edges.count <= 4096 else { throw Failure.capacity }
        guard c.metadataKeys.count + c.metricKeys.count <= 128 else { throw Failure.capacity }
        let ids = document.nodes.map(\.id).sorted()
        guard Set(ids).count == ids.count, Set(document.edges.map(\.id)).count == document.edges.count else { throw Failure.invalidGraph }
        let nodeMap = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })
        let samples = document.nodes.filter { $0.role == c.role }.sorted { $0.id < $1.id }
        guard samples.count >= 2 else { throw Failure.noFeatures }
        let sampleIndices = Dictionary(uniqueKeysWithValues: samples.enumerated().map { ($0.element.id, $0.offset) })
        var raw = Array(repeating: [Key: Double](), count: samples.count)
        var titles: [Key: String] = [:]
        var adjacency: [String: Set<String>] = [:]
        for edge in document.edges.sorted(by: { $0.id < $1.id }) {
            guard nodeMap[edge.sourceID] != nil, nodeMap[edge.targetID] != nil else { throw Failure.invalidGraph }
            adjacency[edge.sourceID, default: []].insert(edge.targetID)
            adjacency[edge.targetID, default: []].insert(edge.sourceID)
            if edge.edgeKind == .instanceOf, c.typeWeight > 0, let index = sampleIndices[edge.sourceID] {
                let key = Key.type(edge.targetID)
                raw[index][key] = sqrt(c.typeWeight)
                titles[key] = "Type: " + (nodeMap[edge.targetID]?.label ?? edge.targetID)
            } else if c.relationshipWeight > 0, edge.edgeKind != .instanceOf {
                for incoming in [false, true] {
                    let subject = incoming ? edge.targetID : edge.sourceID
                    let target = incoming ? edge.sourceID : edge.targetID
                    if let index = sampleIndices[subject] {
                        let key = Key.relation(incoming, edge.ontologyProperty ?? edge.label, target)
                        raw[index][key] = sqrt(c.relationshipWeight)
                        titles[key] = (incoming ? "Incoming " : "Outgoing ") + edge.label + ": " + (nodeMap[target]?.label ?? target)
                            + " [" + (edge.ontologyProperty ?? edge.label) + " → " + target + "]"
                    }
                }
            }
        }
        for (index, node) in samples.enumerated() {
            if c.typeWeight > 0, let type = node.ontologyClass {
                let key = Key.type(type); raw[index][key] = sqrt(c.typeWeight)
                titles[key] = "Type: " + (nodeMap[type]?.label ?? localName(type))
            }
            if c.attributeWeight > 0 {
                for name in c.metadataKeys.sorted() {
                    if let value = node.metadata[name], !value.isEmpty {
                        let key = Key.attribute(name, value); raw[index][key] = sqrt(c.attributeWeight)
                        titles[key] = name + ": " + value
                    }
                }
            }
        }
        if c.attributeWeight > 0 {
            for name in c.metricKeys.sorted() {
                let observed = samples.compactMap { $0.metrics[name] }
                guard observed.allSatisfy(\.isFinite) else { throw Failure.invalidMetric(name) }
                guard !observed.isEmpty else { continue }
                let mean = observed.reduce(0, +) / Double(observed.count)
                let variance = observed.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(observed.count)
                guard mean.isFinite, variance.isFinite else { throw Failure.invalidMetric(name) }
                let deviation = sqrt(variance)
                for (index, node) in samples.enumerated() {
                    if let value = node.metrics[name], deviation > 1e-12 {
                        let key = Key.numeric(name); raw[index][key] = (value - mean) / deviation * sqrt(c.attributeWeight)
                        titles[key] = "Standardized " + name
                    } else if node.metrics[name] == nil {
                        let key = Key.missing(name); raw[index][key] = sqrt(c.attributeWeight)
                        titles[key] = "Missing " + name
                    }
                }
            }
        }
        try checkpoint()
        var frequency: [Key: Int] = [:]
        for row in raw { for key in row.keys { frequency[key, default: 0] += 1 } }
        let keys = frequency.keys.filter { key in
            if case .numeric = key { return true }
            let count = frequency[key] ?? 0
            if case .missing = key { return count > 0 && count < samples.count }
            return count >= 2 && count < samples.count
        }.sorted { $0.order.lexicographicallyPrecedes($1.order) }
        guard !keys.isEmpty else { throw Failure.noFeatures }
        guard keys.count <= 8192 else { throw Failure.capacity }
        let columns = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element, $0.offset) })
        var rows: [[Entry]] = [], activeIDs: [String] = [], unassigned: Set<String> = [], entries = 0
        for (index, row) in raw.enumerated() {
            var sparse: [Entry] = []
            for (key, value) in row {
                guard let column = columns[key] else { continue }
                let factor: Double
                if case .numeric = key { factor = 1 } else { factor = log(Double(samples.count + 1) / Double((frequency[key] ?? 0) + 1)) + 1 }
                if value != 0 { sparse.append(Entry(column: column, value: value * factor)) }
            }
            sparse.sort { $0.column < $1.column }
            let norm = sqrt(sparse.reduce(0) { $0 + $1.value * $1.value })
            guard norm.isFinite else { throw Failure.capacity }
            if norm < 1e-12 { unassigned.insert(samples[index].id); continue }
            sparse = sparse.map { Entry(column: $0.column, value: $0.value / norm) }
            entries += sparse.count
            guard entries <= 65536 else { throw Failure.capacity }
            rows.append(sparse); activeIDs.append(samples[index].id)
        }
        guard rows.count >= 2 else { throw Failure.noFeatures }
        // Centroids are the one required dense feature-space ownership boundary.
        func dense(_ row: [Entry]) -> [Double] {
            var result = Array(repeating: 0.0, count: keys.count)
            for entry in row { result[entry.column] = entry.value }
            return result
        }
        func dot(_ row: [Entry], _ vector: [Double]) -> Double {
            var value = 0.0
            for entry in row { value += entry.value * vector[entry.column] }
            return value
        }
        func squaredNorm(_ vector: [Double]) -> Double { vector.reduce(0) { $0 + $1 * $1 } }
        func distance(_ row: [Entry], _ center: [Double], _ norm: Double) -> Double { max(0, 1 + norm - 2 * dot(row, center)) }
        var centroids = [dense(rows[0])], nearest = Array(repeating: Double.infinity, count: rows.count)
        while centroids.count < min(c.clusterCount, rows.count) {
            let center = centroids[centroids.count - 1], norm = squaredNorm(center)
            for index in rows.indices { nearest[index] = min(nearest[index], distance(rows[index], center, norm)) }
            let farthest = nearest.indices.max { nearest[$0] == nearest[$1] ? $0 > $1 : nearest[$0] < nearest[$1] } ?? 0
            if nearest[farthest] < 1e-12 { break }
            centroids.append(dense(rows[farthest]))
        }
        var assignments = Array(repeating: -1, count: rows.count), iterations = 0, converged = false
        for iteration in 0..<40 {
            try checkpoint(); iterations = iteration + 1
            let norms = centroids.map(squaredNorm)
            var changed = false
            for index in rows.indices {
                var best = 0, bestDistance = Double.infinity
                for cluster in centroids.indices {
                    let value = distance(rows[index], centroids[cluster], norms[cluster])
                    if value < bestDistance { best = cluster; bestDistance = value }
                }
                if assignments[index] != best { changed = true; assignments[index] = best }
            }
            if !changed { converged = true; break }
            var sums = Array(repeating: Array(repeating: 0.0, count: keys.count), count: centroids.count)
            var counts = Array(repeating: 0, count: centroids.count)
            for index in rows.indices {
                let group = assignments[index]; counts[group] += 1
                for entry in rows[index] { sums[group][entry.column] += entry.value }
            }
            for group in centroids.indices where counts[group] > 0 {
                for column in keys.indices { sums[group][column] /= Double(counts[group]) }
                centroids[group] = sums[group]
            }
            await Task.yield()
        }
        guard converged else { throw Failure.convergenceLimit }
        var mean = Array(repeating: 0.0, count: keys.count)
        for row in rows { for entry in row { mean[entry.column] += entry.value / Double(rows.count) } }
        // Implicit centered covariance avoids an N×N distance matrix or dense sample rows.
        func covariance(_ vector: [Double]) -> [Double] {
            let offset = zip(mean, vector).reduce(0) { $0 + $1.0 * $1.1 }
            var output = Array(repeating: 0.0, count: keys.count), sum = 0.0
            for row in rows {
                let score = dot(row, vector) - offset; sum += score
                for entry in row { output[entry.column] += entry.value * score }
            }
            for column in keys.indices { output[column] -= mean[column] * sum }
            return output
        }
        var components: [[Double]] = [], variances: [Double] = []
        for component in 0..<2 {
            var vector = keys.indices.map { sin(Double($0 + 1) * 1.71 + Double(component) * 0.73) }
            for _ in 0..<48 {
                try checkpoint()
                var next = covariance(vector)
                for previous in components {
                    let projection = zip(next, previous).reduce(0) { $0 + $1.0 * $1.1 }
                    for column in keys.indices { next[column] -= projection * previous[column] }
                }
                let norm = sqrt(squaredNorm(next))
                if norm < 1e-12 { vector = Array(repeating: 0, count: keys.count); break }
                for column in keys.indices { next[column] /= norm }
                vector = next
            }
            if let dominant = vector.indices.max(by: { abs(vector[$0]) < abs(vector[$1]) }), vector[dominant] < 0 {
                for column in keys.indices { vector[column] = -vector[column] }
            }
            let applied = covariance(vector)
            variances.append(max(0, zip(vector, applied).reduce(0) { $0 + $1.0 * $1.1 }))
            components.append(vector)
            await Task.yield()
        }
        let offsets = components.map { component in zip(mean, component).reduce(0) { $0 + $1.0 * $1.1 } }
        var positions: [String: SIMD2<Double>] = [:]
        for index in rows.indices { positions[activeIDs[index]] = SIMD2(dot(rows[index], components[0]) - offsets[0], dot(rows[index], components[1]) - offsets[1]) }
        let magnitude = positions.values.reduce(0) { max($0, max(abs($1.x), abs($1.y))) }
        if magnitude > 1e-12 { for id in activeIDs { positions[id]! *= 4 / magnitude } }
        let groups = Dictionary(grouping: rows.indices, by: { assignments[$0] }).values.sorted { activeIDs[$0[0]] < activeIDs[$1[0]] }
        var clusters: [GraphClusterResult.Cluster] = [], membership: [String: Int] = [:]
        for (group, indices) in groups.enumerated() {
            let members = indices.map { activeIDs[$0] }
            var strengths = Array(repeating: 0.0, count: keys.count)
            var center = SIMD2<Double>.zero
            for index in indices {
                membership[activeIDs[index]] = group; center += positions[activeIDs[index]]!
                for entry in rows[index] { strengths[entry.column] += entry.value / Double(indices.count) }
            }
            let strongest = strengths.indices.filter { abs(strengths[$0]) > 1e-9 }.sorted { abs(strengths[$0]) == abs(strengths[$1]) ? $0 < $1 : abs(strengths[$0]) > abs(strengths[$1]) }.prefix(4)
            clusters.append(.init(id: group, members: members, center: center / Double(members.count), features: strongest.map { (strengths[$0] < 0 ? "Below mean · " : "") + (titles[keys[$0]] ?? "Feature") }))
        }
        var depths = Dictionary(uniqueKeysWithValues: activeIDs.map { ($0, 0) }), pending = activeIDs
        var cursor = 0
        while cursor < pending.count {
            let id = pending[cursor]; cursor += 1
            for neighbor in (adjacency[id] ?? []).sorted() where depths[neighbor] == nil {
                depths[neighbor] = depths[id]! + 1; pending.append(neighbor)
            }
        }
        for id in pending where positions[id] == nil {
            let predecessors = (adjacency[id] ?? []).filter { (depths[$0] ?? Int.max) < depths[id]! }.sorted()
            var sum = SIMD2<Double>.zero, count = 0
            for predecessor in predecessors { if let point = positions[predecessor] { sum += point; count += 1 } }
            if count > 0 { positions[id] = sum / Double(count) }
        }
        // Excluded samples remain excluded even if connected to analyzed samples.
        let unpositioned = Set(ids.filter { positions[$0] == nil }).union(unassigned)
        for (index, id) in unpositioned.sorted().enumerated() { positions[id] = SIMD2(6 + Double(index % 8) * 0.25, -4 + Double(index / 8) * 0.25) }
        try checkpoint()
        let totalVariance = Double(rows.count) * max(0, 1 - squaredNorm(mean))
        return GraphClusterResult(configuration: c, clusters: clusters, membership: membership, positions: positions,
                                  unpositionedIDs: unpositioned, unassignedIDs: unassigned, featureCount: keys.count,
                                  retainedVariance: totalVariance > 1e-12 ? min(1, variances.reduce(0, +) / totalVariance) : 0,
                                  iterations: iterations)
    }
}
