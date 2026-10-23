import SwiftUI
import Charts

struct AnalysisChartView: View {
    let data: AnalysisChartData
    let kind: AnalysisChartKind
    let featureID: String?
    let selectedRows: Set<Int>
    let selectedCluster: Int?
    let onSelectRow: (Int?) -> Void
    let onSelectCluster: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch kind {
            case .scatter: scatter
            case .counts: counts
            case .profiles:
                if let feature = data.features.first(where: { $0.id == featureID }) ?? data.features.first {
                    profiles(feature)
                } else {
                    ContentUnavailableView("No Numeric Profiles", systemImage: "chart.bar", description: Text("Choose numeric measurements to compare their original-value quartiles."))
                }
            }
            Text("\(data.points.count) analyzed · \(data.excludedCount) excluded · " + description)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("analysis.chart.coverage")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("analysis.chart." + kind.rawValue)
    }

    private var description: String {
        switch kind {
        case .scatter: data.projectionDescription
        case .counts: "Counts describe this analysis population. Select a bar to inspect its source rows."
        case .profiles: "Original values: median and Q1–Q3; dashed line is the analyzed population median."
        }
    }

    private var scatter: some View {
        Chart(data.points) { point in
            PointMark(x: .value(data.xTitle, point.x), y: .value(data.yTitle, point.y))
                .foregroundStyle(by: .value("Cluster", point.clusterLabel))
                .symbolSize(selectedRows.contains(point.id) ? 100 : 24)
                .opacity(selectedRows.isEmpty || selectedRows.contains(point.id) ? 0.9 : 0.25)
                .accessibilityLabel("Row \(point.id + 1), \(point.clusterLabel)")
                .accessibilityValue("\(data.xTitle): \(point.x.formatted()), \(data.yTitle): \(point.y.formatted())")
        }
        .chartXAxisLabel(data.xTitle)
        .chartYAxisLabel(data.yTitle)
        .chartForegroundStyleScale(domain: data.groups.map(\.label), range: data.groups.map { GraphClusterPalette.color($0.id) })
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { event in
                        guard let anchor = proxy.plotFrame else { return }
                        let frame = geometry[anchor]
                        guard frame.contains(event.location) else { return }
                        let location = CGPoint(x: event.location.x - frame.minX, y: event.location.y - frame.minY)
                        var nearest: Int?, distance = 12.0 * 12.0
                        for point in data.points {
                            guard let x = proxy.position(forX: point.x), let y = proxy.position(forY: point.y) else { continue }
                            let candidate = pow(x - location.x, 2) + pow(y - location.y, 2)
                            if candidate < distance { nearest = point.id; distance = candidate }
                        }
                        onSelectRow(nearest)
                    })
            }
        }
    }

    private var counts: some View {
        Chart(data.groups) { group in
            BarMark(x: .value("Rows", group.rowIDs.count), y: .value("Cluster", group.label))
                .foregroundStyle(GraphClusterPalette.color(group.id))
                .opacity(selectedCluster == nil || selectedCluster == group.id ? 0.9 : 0.25)
                .annotation(position: .trailing) { Text(group.rowIDs.count, format: .number).font(.caption) }
                .accessibilityLabel(group.label).accessibilityValue("\(group.rowIDs.count) rows")
        }
        .chartXAxisLabel("Analyzed rows")
        .chartYScale(domain: data.groups.map(\.label))
        .chartOverlay { proxy in groupPicking(proxy) }
    }

    private func profiles(_ feature: AnalysisChartData.Feature) -> some View {
        Chart {
            ForEach(feature.profiles) { profile in
                RuleMark(xStart: .value("Q1", profile.lowerQuartile), xEnd: .value("Q3", profile.upperQuartile), y: .value("Cluster", profile.clusterLabel))
                    .foregroundStyle(GraphClusterPalette.color(profile.id)).lineStyle(StrokeStyle(lineWidth: 5))
                    .opacity(selectedCluster == nil || selectedCluster == profile.id ? 0.8 : 0.25)
                    .accessibilityLabel(profile.clusterLabel + " interquartile range")
                    .accessibilityValue("\(profile.lowerQuartile.formatted()) to \(profile.upperQuartile.formatted())")
                PointMark(x: .value("Median", profile.median), y: .value("Cluster", profile.clusterLabel))
                    .foregroundStyle(GraphClusterPalette.color(profile.id)).symbol(.diamond).symbolSize(80)
                    .accessibilityLabel(profile.clusterLabel + " median").accessibilityValue(profile.median.formatted())
            }
            RuleMark(x: .value("Population median", feature.populationMedian))
                .foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [4, 4]))
                .accessibilityLabel("Population median").accessibilityValue(feature.populationMedian.formatted())
        }
        .chartXAxisLabel(feature.title + " · original values")
        .chartYScale(domain: data.groups.map(\.label))
        .chartOverlay { proxy in groupPicking(proxy) }
    }

    private func groupPicking(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { event in
                    guard let anchor = proxy.plotFrame else { return }
                    let frame = geometry[anchor]
                    guard frame.contains(event.location),
                          let label = proxy.value(atY: event.location.y - frame.minY, as: String.self) else { return }
                    onSelectCluster(data.groups.first(where: { $0.label == label })?.id)
                })
        }
    }
}
