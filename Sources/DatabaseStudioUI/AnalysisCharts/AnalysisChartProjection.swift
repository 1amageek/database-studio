import Foundation

struct AnalysisChartProjection: AnalysisChartProjecting {
    enum Failure: Error, LocalizedError {
        case capacity
        case invalidResult
        var errorDescription: String? {
            switch self {
            case .capacity: "The analysis exceeds chart capacity."
            case .invalidResult: "The analysis contains invalid coordinates, row identities or cluster profiles."
            }
        }
    }

    @concurrent func project(_ result: GraphClusterResult, rowCount: Int) async throws -> AnalysisChartData {
        try Task.checkCancellation()
        guard rowCount <= GraphNumericAnalyzer.maximumNodes, result.clusters.count <= 24,
              result.configuration.numericFeatures.count <= 32 else { throw Failure.capacity }
        guard rowCount > 0, !result.membership.isEmpty,
              result.axes.isEmpty || result.axes.count == 2,
              result.axes.allSatisfy({ $0.lower.isFinite && $0.upper.isFinite && $0.upper >= $0.lower }),
              result.retainedVariance.isFinite, (0...1).contains(result.retainedVariance),
              result.unassignedIDs.isDisjoint(with: result.membership.keys),
              Set(result.clusters.map(\.id)).count == result.clusters.count else { throw Failure.invalidResult }

        func rowID(_ id: String) throws -> Int {
            guard let row = RecordAnalysisSource.rowIndex(id), (0..<rowCount).contains(row),
                  id == "page-row:\(row)" else { throw Failure.invalidResult }
            return row
        }
        var groups: [AnalysisChartData.Group] = []
        var declaredMembers = Set<String>()
        for cluster in result.clusters.sorted(by: { $0.id < $1.id }) {
            guard cluster.id >= 0, !cluster.members.isEmpty else { throw Failure.invalidResult }
            var rows: [Int] = []
            for id in cluster.members {
                guard declaredMembers.insert(id).inserted, result.membership[id] == cluster.id else { throw Failure.invalidResult }
                rows.append(try rowID(id))
            }
            groups.append(.init(id: cluster.id, rowIDs: rows.sorted()))
        }
        guard declaredMembers == Set(result.membership.keys) else { throw Failure.invalidResult }
        for id in result.unassignedIDs { _ = try rowID(id) }
        var points: [AnalysisChartData.Point] = []
        points.reserveCapacity(result.membership.count)
        for (offset, id) in result.membership.keys.sorted().enumerated() {
            if offset.isMultiple(of: 256) { try Task.checkCancellation() }
            guard let position = result.positions[id], position.x.isFinite, position.y.isFinite else { throw Failure.invalidResult }
            let x = result.axes.isEmpty ? position.x : result.axes[0].value(at: position.x)
            let y = result.axes.isEmpty ? position.y : result.axes[1].value(at: position.y)
            guard x.isFinite, y.isFinite else { throw Failure.invalidResult }
            points.append(.init(id: try rowID(id), x: x, y: y, clusterID: result.membership[id]!))
        }
        points.sort { $0.id < $1.id }
        var features: [AnalysisChartData.Feature] = []
        for feature in result.configuration.numericFeatures {
            try Task.checkCancellation()
            var profiles: [AnalysisChartData.Profile] = []
            var populationMedian: Double?
            for group in groups {
                guard let profile = result.profiles[group.id]?.first(where: { $0.id == feature.id }),
                      profile.median.isFinite, profile.lowerQuartile.isFinite,
                      profile.upperQuartile.isFinite, profile.populationMedian.isFinite,
                      profile.lowerQuartile <= profile.median, profile.median <= profile.upperQuartile,
                      populationMedian == nil || populationMedian == profile.populationMedian else { throw Failure.invalidResult }
                populationMedian = profile.populationMedian
                profiles.append(.init(id: group.id, median: profile.median, lowerQuartile: profile.lowerQuartile, upperQuartile: profile.upperQuartile))
            }
            guard let populationMedian else { throw Failure.invalidResult }
            features.append(.init(id: feature.id, title: feature.title, populationMedian: populationMedian, profiles: profiles))
        }
        try Task.checkCancellation()
        return AnalysisChartData(points: points, groups: groups, features: features,
                                 xTitle: result.axes.first?.title ?? "Principal component 1 · display units",
                                 yTitle: result.axes.last?.title ?? "Principal component 2 · display units",
                                 projectionDescription: result.axes.isEmpty ? "PCA retains \(Int(result.retainedVariance * 100))% of variance; membership uses all configured features." : "Axes show transformed, robust units; membership uses all configured features.",
                                 excludedCount: result.unassignedIDs.count)
    }
}
