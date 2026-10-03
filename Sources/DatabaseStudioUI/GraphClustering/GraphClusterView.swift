import SwiftUI

struct GraphClusterView: View {
    @Bindable var state: GraphViewState

    var body: some View {
        GeometryReader { proxy in
            if let result = state.clusterSession.result {
                CanvasInteractionView(onScroll: { x, y in
                    state.clusterSession.cameraOffset.width += x
                    state.clusterSession.cameraOffset.height += y
                }, onMagnify: { amount, point in
                    let session = state.clusterSession, old = session.cameraScale
                    session.cameraScale = min(8, max(0.1, old * (1 + amount)))
                    let ratio = session.cameraScale / old
                    session.cameraOffset = CGSize(width: point.x - proxy.size.width / 2 - (point.x - proxy.size.width / 2 - session.cameraOffset.width) * ratio,
                                                  height: point.y - proxy.size.height / 2 - (point.y - proxy.size.height / 2 - session.cameraOffset.height) * ratio)
                }) {
                    Canvas { context, size in draw(result: result, context: &context, size: size) }
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { event in
                            let ids = sampleIDs(result: result)
                            let nearest = ids.min { screen(result.positions[$0]!, size: proxy.size).distance(to: event.location) < screen(result.positions[$1]!, size: proxy.size).distance(to: event.location) }
                            if let nearest, screen(result.positions[nearest]!, size: proxy.size).distance(to: event.location) <= 12 {
                                state.clusterSession.selectedCluster = result.membership[nearest]
                                state.selectNode(nearest)
                            } else { state.clusterSession.selectedCluster = nil; state.selectNode(nil) }
                        })
                        .accessibilityIdentifier("graph.cluster.viewport")
                        .accessibilityLabel("Feature clusters. Positions use the configured axes or a PCA projection. Scroll to pan, pinch to zoom, select a cluster for its features and members.")
                }
            } else if let failure = state.clusterSession.failure {
                ContentUnavailableView("Feature Analysis Unavailable", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else if !state.clusterSession.isLoading {
                ContentUnavailableView("Configure Your Analysis", systemImage: "chart.xyaxis.line", description: Text("Choose numeric columns or graph features, then run the analysis."))
            } else {
                ProgressView("Analyzing graph features…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottomLeading) { GraphClusterControls(state: state) }
        .task(id: state.clusterSession.revision) { if state.clusterSession.configuration.mode != .numeric || !state.clusterSession.configuration.numericFeatures.isEmpty { await state.clusterSession.prepare(document: state.document) } }
        .onDisappear { state.clusterSession.cancel() }
    }

    private func sampleIDs(result: GraphClusterResult) -> [String] {
        let visible = state.visibleNodeIDs
        return result.membership.keys.filter { visible.contains($0) }.sorted()
            + result.unassignedIDs.filter { visible.contains($0) }.sorted()
    }

    private func screen(_ point: SIMD2<Double>, size: CGSize) -> CGPoint {
        let session = state.clusterSession
        let unit = min(size.width / session.coordinateExtent.x, size.height / session.coordinateExtent.y) * session.cameraScale
        let offset = point - session.coordinateCenter
        return CGPoint(x: size.width / 2 + offset.x * unit + session.cameraOffset.width,
                       y: size.height / 2 - offset.y * unit + session.cameraOffset.height)
    }

    private func draw(result: GraphClusterResult, context: inout GraphicsContext, size: CGSize) {
        if result.axes.count == 2 {
            let origin = screen(SIMD2(-4, -4), size: size), right = screen(SIMD2(4, -4), size: size), top = screen(SIMD2(-4, 4), size: size)
            var path = Path(); path.move(to: top); path.addLine(to: origin); path.addLine(to: right)
            context.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 0.7)
            for tick in [-4.0, -2, 0, 2, 4] {
                let x = screen(SIMD2(tick, -4), size: size), y = screen(SIMD2(-4, tick), size: size)
                context.draw(Text(result.axes[0].value(at: tick), format: .number.precision(.significantDigits(3))).font(.caption2).foregroundColor(.secondary), at: CGPoint(x: x.x, y: x.y + 12))
                context.draw(Text(result.axes[1].value(at: tick), format: .number.precision(.significantDigits(3))).font(.caption2).foregroundColor(.secondary), at: CGPoint(x: y.x - 8, y: y.y), anchor: .trailing)
            }
            context.draw(Text(result.axes[0].title).font(.caption2).foregroundColor(.secondary), at: CGPoint(x: (origin.x + right.x) / 2, y: origin.y + 30))
            context.draw(Text(result.axes[1].title).font(.caption2).foregroundColor(.secondary), at: CGPoint(x: top.x, y: top.y - 16), anchor: .leading)
        }
        let selected = state.clusterSession.selectedCluster
        for id in sampleIDs(result: result) {
            guard let position = result.positions[id] else { continue }
            let point = screen(position, size: size)
            let cluster = result.membership[id]
            let color = cluster.map(GraphClusterPalette.color) ?? .secondary
            let radius: CGFloat = state.selectedNodeID == id ? 5 : 2.5
            let shape = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(shape, with: .color(color.opacity(selected == nil || selected == cluster ? 0.85 : 0.18)))
            if state.selectedNodeID == id { context.stroke(shape, with: .color(.primary), lineWidth: 1.2) }
        }
        var occupied: [CGRect] = []
        for cluster in result.clusters {
            let point = screen(cluster.center, size: size)
            var labelPoint = CGPoint(x: point.x, y: point.y - 18)
            let text = context.resolve(Text("Cluster \(cluster.id + 1) · \(cluster.members.count)").font(.caption2).foregroundColor(GraphClusterPalette.color(cluster.id)))
            let measured = text.measure(in: CGSize(width: 150, height: 25))
            var rect = CGRect(x: labelPoint.x - measured.width / 2, y: labelPoint.y - measured.height / 2, width: measured.width, height: measured.height)
            for _ in 0..<4 where occupied.contains(where: { $0.intersects(rect) }) { labelPoint.y -= 18; rect.origin.y -= 18 }
            occupied.append(rect); context.draw(text, at: labelPoint)
        }
        if !result.unpositionedIDs.isEmpty {
            context.draw(Text("Unpositioned").font(.caption2).foregroundColor(.secondary), at: screen(SIMD2(6.7, -4.5), size: size))
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}
