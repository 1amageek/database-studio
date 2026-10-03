import Foundation

struct GraphNumericAnalyzer: GraphClusterAnalyzing {
    static let maximumNodes = 10_000

    @concurrent func analyze(document: GraphDocument, configuration c: GraphClusterConfiguration) async throws -> GraphClusterResult {
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(10))
        func checkpoint() throws {
            try Task.checkCancellation()
            if clock.now > deadline { throw GraphFeatureAnalyzer.Failure.elapsedLimit }
        }
        try checkpoint()
        let features = c.numericFeatures
        guard (2...24).contains(c.clusterCount), !features.isEmpty, features.count <= 32,
              Set(features.map(\.id)).count == features.count,
              features.allSatisfy({ $0.weight.isFinite && (0...8).contains($0.weight) }),
              features.contains(where: { $0.weight > 0 }) else { throw GraphFeatureAnalyzer.Failure.invalidConfiguration }
        guard document.nodes.count <= Self.maximumNodes, document.edges.count <= 4096 else { throw GraphFeatureAnalyzer.Failure.capacity }
        let ids = Set(document.nodes.map(\.id))
        guard ids.count == document.nodes.count, Set(document.edges.map(\.id)).count == document.edges.count,
              document.edges.allSatisfy({ ids.contains($0.sourceID) && ids.contains($0.targetID) }) else { throw GraphFeatureAnalyzer.Failure.invalidGraph }
        var samples: [GraphNode] = [], originals: [[Double]] = [], transformed: [[Double]] = []
        var excluded: [String: String] = [:]
        for node in document.nodes.filter({ $0.role == c.role }).sorted(by: { $0.id < $1.id }) {
            try checkpoint()
            if c.excludesFlaggedRows, let flags = node.metadata["Quality flags"], !flags.isEmpty { excluded[node.id] = flags; continue }
            var raw: [Double] = [], values: [Double] = []
            for feature in features {
                for key in [feature.numerator, feature.denominator].compactMap({ $0 }) {
                    if let value = node.metrics[key], !value.isFinite { throw GraphFeatureAnalyzer.Failure.invalidMetric(key) }
                }
                guard let value = feature.value(in: node), let converted = feature.transformed(value) else {
                    excluded[node.id] = "Missing value, nonpositive divisor or invalid transform: " + feature.title
                    break
                }
                raw.append(value); values.append(converted)
            }
            if values.count == features.count { samples.append(node); originals.append(raw); transformed.append(values) }
        }
        if let key = c.comparisonKey {
            let counts = Dictionary(grouping: samples.indices, by: { samples[$0].metadata[key] ?? "" }).mapValues(\.count)
            var kept: [GraphNode] = [], raw: [[Double]] = [], values: [[Double]] = []
            for i in samples.indices {
                let group = samples[i].metadata[key] ?? ""
                if group.isEmpty || counts[group, default: 0] < 2 { excluded[samples[i].id] = "Missing or singleton comparison group: " + key }
                else { kept.append(samples[i]); raw.append(originals[i]); values.append(transformed[i]) }
            }
            samples = kept; originals = raw; transformed = values
        }
        guard samples.count >= 2 else { throw GraphFeatureAnalyzer.Failure.noFeatures }
        let width = features.count, count = samples.count
        for column in features.indices {
            let sorted = transformed.map { $0[column] }.sorted()
            let median = quantile(sorted, 0.5), iqr = quantile(sorted, 0.75) - quantile(sorted, 0.25)
            // A zero IQR uses one transformed unit, retaining a varying minority.
            let scale = iqr > 0 ? iqr : 1
            for row in transformed.indices { transformed[row][column] = (transformed[row][column] - median) / scale }
        }
        if let key = c.comparisonKey {
            let groups = Dictionary(grouping: samples.indices, by: { samples[$0].metadata[key]! })
            for group in groups.values {
                for column in features.indices {
                    let median = quantile(group.map { transformed[$0][column] }.sorted(), 0.5)
                    for row in group { transformed[row][column] -= median }
                }
            }
        }
        // Dense materialization owns the transformed table across clustering and PCA.
        var matrix = Array(repeating: 0.0, count: count * width)
        for row in samples.indices { for column in features.indices { matrix[row * width + column] = transformed[row][column] * sqrt(features[column].weight) } }
        guard matrix.allSatisfy(\.isFinite) else { throw GraphFeatureAnalyzer.Failure.invalidConfiguration }
        func distance(_ row: Int, _ center: [Double]) -> Double {
            var value = 0.0
            for column in features.indices { let delta = matrix[row * width + column] - center[column]; value += delta * delta }
            return value
        }
        func row(_ index: Int) -> [Double] { Array(matrix[(index * width)..<((index + 1) * width)]) }
        var centers = [row(0)], nearest = Array(repeating: Double.infinity, count: count)
        while centers.count < min(c.clusterCount, count) {
            try checkpoint()
            for i in samples.indices { nearest[i] = min(nearest[i], distance(i, centers.last!)) }
            guard nearest.allSatisfy(\.isFinite) else { throw GraphFeatureAnalyzer.Failure.invalidConfiguration }
            let farthest = nearest.indices.max { nearest[$0] == nearest[$1] ? $0 > $1 : nearest[$0] < nearest[$1] }!
            if nearest[farthest] < 1e-12 { break }
            centers.append(row(farthest))
        }
        guard centers.count >= 2 else { throw GraphFeatureAnalyzer.Failure.noFeatures }
        var assignments = Array(repeating: -1, count: count), iterations = 0, converged = false
        for iteration in 0..<100 {
            try checkpoint(); iterations = iteration + 1
            var changed = false
            for i in samples.indices {
                var best = 0, minimum = Double.infinity
                for group in centers.indices { let value = distance(i, centers[group]); if value < minimum { best = group; minimum = value } }
                if assignments[i] != best { assignments[i] = best; changed = true }
            }
            if !changed { converged = true; break }
            var sums = Array(repeating: Array(repeating: 0.0, count: width), count: centers.count)
            var sizes = Array(repeating: 0, count: centers.count)
            for i in samples.indices { sizes[assignments[i]] += 1; for column in features.indices { sums[assignments[i]][column] += matrix[i * width + column] } }
            for group in centers.indices where sizes[group] > 0 { for column in features.indices { centers[group][column] = sums[group][column] / Double(sizes[group]) } }
            await Task.yield()
        }
        guard converged else { throw GraphFeatureAnalyzer.Failure.convergenceLimit }
        var positions: [String: SIMD2<Double>] = [:], axes: [GraphAnalysisAxis] = [], retainedVariance = 0.0
        if c.projection == .axes {
            let x = features.firstIndex(where: { $0.id == c.xFeatureID }) ?? 0
            let y = features.firstIndex(where: { $0.id == c.yFeatureID }) ?? min(1, width - 1)
            for column in [x, y] {
                let values = transformed.map { $0[column] }
                axes.append(GraphAnalysisAxis(title: features[column].axisTitle + (c.comparisonKey == nil ? "" : " · peer centered"), lower: values.min()!, upper: values.max()!))
            }
            for i in samples.indices { positions[samples[i].id] = SIMD2(axes[0].coordinate(transformed[i][x]), axes[1].coordinate(transformed[i][y])) }
        } else {
            var mean = Array(repeating: 0.0, count: width)
            for i in samples.indices { for column in features.indices { mean[column] += matrix[i * width + column] / Double(count) } }
            func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
            func covariance(_ vector: [Double]) -> [Double] {
                var output = Array(repeating: 0.0, count: width)
                for i in samples.indices {
                    var score = 0.0
                    for column in features.indices { score += (matrix[i * width + column] - mean[column]) * vector[column] }
                    for column in features.indices { output[column] += (matrix[i * width + column] - mean[column]) * score }
                }
                return output
            }
            var components: [[Double]] = [], variances: [Double] = []
            for component in 0..<2 {
                var vector = features.indices.map { sin(Double($0 + 1) * 1.71 + Double(component) * 0.73) }
                for _ in 0..<48 {
                    try checkpoint(); var next = covariance(vector)
                    for previous in components { let projection = dot(next, previous); for column in features.indices { next[column] -= projection * previous[column] } }
                    let norm = sqrt(dot(next, next))
                    guard norm.isFinite else { throw GraphFeatureAnalyzer.Failure.invalidConfiguration }
                    if norm < 1e-12 { vector = Array(repeating: 0, count: width); break }
                    for column in features.indices { next[column] /= norm }; vector = next
                }
                let dominant = vector.indices.max { abs(vector[$0]) < abs(vector[$1]) }!
                if vector[dominant] < 0 { for column in features.indices { vector[column] = -vector[column] } }
                variances.append(max(0, dot(vector, covariance(vector)))); components.append(vector)
            }
            var total = 0.0
            for i in samples.indices {
                var point = SIMD2<Double>.zero
                for column in features.indices {
                    let value = matrix[i * width + column] - mean[column]; total += value * value
                    point.x += value * components[0][column]; point.y += value * components[1][column]
                }
                positions[samples[i].id] = point
            }
            let magnitude = positions.values.reduce(0.0) { max($0, max(abs($1.x), abs($1.y))) }
            if magnitude > 0 { for id in positions.keys { positions[id]! *= 4 / magnitude } }
            retainedVariance = total > 0 ? min(1, variances.reduce(0, +) / total) : 0
        }
        let population = features.indices.map { column in quantile(originals.map { $0[column] }.sorted(), 0.5) }
        var membership: [String: Int] = [:], clusters: [GraphClusterResult.Cluster] = [], profiles: [Int: [GraphClusterResult.FeatureProfile]] = [:]
        let groups = Dictionary(grouping: samples.indices, by: { assignments[$0] }).values.sorted { samples[$0[0]].id < samples[$1[0]].id }
        for (group, indices) in groups.enumerated() {
            var center = SIMD2<Double>.zero
            for index in indices { membership[samples[index].id] = group; center += positions[samples[index].id]! }
            profiles[group] = features.indices.map { column in
                let values = indices.map { originals[$0][column] }.sorted()
                return .init(id: features[column].id, title: features[column].title, median: quantile(values, 0.5), lowerQuartile: quantile(values, 0.25), upperQuartile: quantile(values, 0.75), populationMedian: population[column])
            }
            clusters.append(.init(id: group, members: indices.map { samples[$0].id }, center: center / Double(indices.count), features: features.map(\.title)))
        }
        let unpositioned = ids.subtracting(positions.keys)
        for (index, id) in unpositioned.sorted().enumerated() { positions[id] = SIMD2(6 + Double(index % 8) * 0.25, -4 + Double(index / 8) * 0.25) }
        guard positions.values.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw GraphFeatureAnalyzer.Failure.invalidConfiguration }
        try checkpoint()
        return GraphClusterResult(configuration: c, clusters: clusters, membership: membership, positions: positions,
                                  unpositionedIDs: unpositioned, unassignedIDs: Set(excluded.keys), featureCount: width,
                                  retainedVariance: retainedVariance, iterations: iterations, axes: axes, exclusionReasons: excluded, profiles: profiles)
    }

    private func quantile(_ sorted: [Double], _ probability: Double) -> Double {
        let index = Double(sorted.count - 1) * probability, lower = Int(index), upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - Double(lower))
    }
}
