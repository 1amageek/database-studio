import SwiftUI

struct GraphSpatialView: View {
    @Bindable var state: GraphViewState
    @Environment(\.colorScheme) private var colorScheme
    @State private var scene = GraphSpatialScene()
    @State private var drag = CGSize.zero
    @State private var draggedNode: String?
    @State private var dragPlane: SIMD3<Float>?

    var body: some View {
        GeometryReader { proxy in
            if let reason = state.spatialUnavailableReason ?? state.spatialFailureMessage {
                unavailable(reason)
            } else if let layout = state.spatialLayout {
                viewport(layout: layout, size: proxy.size)
            } else {
                ProgressView("Preparing relationship network…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottomLeading) {
            if state.usesFeatureClusters { GraphClusterControls(state: state) }
        }
        .task(id: [state.spatialDocumentRevision, state.clusterSession.revision]) { await state.prepareSpatialLayout() }
        .onDisappear { state.cancelSpatialLayout(); if state.usesFeatureClusters { state.clusterSession.cancel() } }
    }

    private func unavailable(_ reason: String) -> some View {
        ContentUnavailableView {
            Label("3D Network Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(reason)
        } actions: {
            Button("Return to 2D") { state.isSpatial = false }
                .contentShape(Rectangle())
        }
    }

    private func viewport(layout: GraphSpatialLayout, size: CGSize) -> some View {
        CanvasInteractionView(onScroll: { x, y in
            state.spatialCamera.pan(dx: x, dy: y, height: size.height)
        }, onMagnify: { delta, _ in state.spatialCamera.zoom(delta) }, onThreeFingerOrbit: { x, y, roll in
            state.spatialCamera.rotateNetwork(dx: x, dy: y, roll: roll)
        }) {
            ZStack {
                Canvas { context, size in draw(context: &context, layout: layout, size: size) }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { event in
                        project(layout: layout, size: size)
                        state.selectNode(scene.hit(at: event.location))
                    })
                    .gesture(DragGesture(minimumDistance: 3).onChanged { event in
                        state.spatialCamera.orbit(dx: event.translation.width - drag.width,
                                                  dy: event.translation.height - drag.height)
                        drag = event.translation
                    }.onEnded { _ in drag = .zero })
                    .gesture(DragGesture(minimumDistance: 3).modifiers(.option).onChanged { event in
                        guard !state.usesFeatureClusters else { return }
                        if dragPlane == nil {
                            project(layout: layout, size: size)
                            draggedNode = scene.hit(at: event.startLocation)
                            dragPlane = draggedNode.flatMap { layout.positions[$0] }
                        }
                        if let draggedNode, let dragPlane {
                            state.moveSpatialNode(draggedNode, screen: event.location, planePoint: dragPlane)
                        }
                    }.onEnded { _ in draggedNode = nil; dragPlane = nil })
                    .accessibilityIdentifier("graph.spatial.viewport")
                    .accessibilityLabel(state.usesFeatureClusters
                        ? "Feature layers. Three-finger drag to orbit and twist to roll. Mouse drag to orbit, scroll to pan, pinch to zoom. Layer height represents the configured category or node role; planar positions preserve the two-dimensional feature projection."
                        : "Relationship network. Three-finger drag to orbit and twist to roll. Mouse drag to orbit, scroll to pan, pinch to zoom. Option-drag moves a display point.")
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !state.usesFeatureClusters {
            VStack(alignment: .leading, spacing: 3) {
                Text("Relationship network").font(.caption.weight(.semibold))
                Text("\(state.visibleNodes.count) points · \(state.visibleEdges.count) relationships")
                    .font(.caption2).foregroundStyle(.secondary)
                if state.visibleNodes.count > 32 {
                    Text("Up to 32 labels · Zoom in or select a point for details")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("Three-finger drag / twist to rotate · Option-drag to arrange")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(12)
            }
        }
        .onAppear {
            let firstViewport = state.spatialViewport == .zero
            state.spatialViewport = size
            if firstViewport { state.fitSpatialCamera() }
        }
        .onChange(of: size) { _, size in state.spatialViewport = size }
    }

    private func project(layout: GraphSpatialLayout, size: CGSize) {
        scene.update(layout: layout, revision: state.spatialGeometryRevision, edges: state.visibleEdges)
        scene.project(camera: state.spatialCamera, layout: layout, revision: state.spatialGeometryRevision,
                      nodes: state.visibleNodes, selectedID: state.selectedNodeID, size: size,
                      emphasizedIDs: state.usesFeatureClusters ? state.clusterSession.emphasizedIDs : [])
    }

    private func draw(context: inout GraphicsContext, layout: GraphSpatialLayout, size: CGSize) {
        project(layout: layout, size: size)
        for layer in layout.layers {
            let points = layer.corners.compactMap { state.spatialCamera.project($0, size: size)?.point }
            if points.count == 4 {
                var path = Path(); path.addLines(points); path.closeSubpath()
                context.fill(path, with: .color(.primary.opacity(0.018)))
                context.stroke(path, with: .color(.primary.opacity(0.09)), lineWidth: 0.5)
                let labelPoint = CGPoint(x: points[0].x + 8, y: points[0].y - 10)
                context.draw(Text("\(layer.title) · \(layer.count)").font(.caption2).foregroundColor(.secondary), at: labelPoint, anchor: .leading)
            }
        }
        if state.usesFeatureClusters, let result = state.clusterSession.result {
            for layer in layout.layers {
                let points = state.document.nodes.lazy.filter { layer.nodeIDs.contains($0.id) && result.unpositionedIDs.contains($0.id) }
                    .compactMap { layout.positions[$0.id] }
                if let first = points.first {
                    let lower = points.reduce(first) { SIMD3(min($0.x, $1.x), layer.height, min($0.z, $1.z)) }
                    if let point = state.spatialCamera.project(lower + SIMD3(0, 0, -0.5), size: size)?.point {
                        context.draw(Text("Unpositioned · \(points.count)").font(.caption2).foregroundColor(.secondary), at: point, anchor: .leading)
                    }
                }
            }
        }
        let colors = state.nodeColorMap
        let icons = state.nodeIconMap
        context.stroke(scene.normalPath, with: .color(.primary.opacity(0.10)), lineWidth: 0.5)
        context.stroke(scene.emphasizedPath, with: .color(.primary.opacity(0.55)), lineWidth: 0.8)
        context.stroke(scene.arrowPath, with: .color(.primary.opacity(0.7)), lineWidth: 0.8)
        for glyph in scene.glyphs {
            let selected = glyph.node.id == state.selectedNodeID
            let style = GraphNodeStyle.style(for: glyph.node.role)
            let cluster = state.usesFeatureClusters ? state.clusterSession.result?.membership[glyph.node.id] : nil
            let unpositioned = state.usesFeatureClusters && (state.clusterSession.result?.unpositionedIDs.contains(glyph.node.id) ?? false)
            let color = unpositioned ? Color.secondary : cluster.map(GraphClusterPalette.color) ?? state.mapping.nodeColor(for: glyph.node, baseColor: colors[glyph.node.id] ?? style.color)
            let highlighted = state.clusterSession.selectedCluster == nil || cluster == state.clusterSession.selectedCluster || cluster == nil
            let shape = glyph.node.role == .type
                ? Path(roundedRect: glyph.rect, cornerRadius: min(2, glyph.radius / 3)) : Path(ellipseIn: glyph.rect)
            context.fill(shape, with: .color(color.opacity(selected ? 1 : highlighted ? 0.7 : 0.18)))
            if selected { context.stroke(shape, with: .color(.primary), lineWidth: 1.5) }
            if glyph.radius >= 7 {
                context.draw(Text(Image(systemName: icons[glyph.node.id] ?? style.iconName))
                    .font(.system(size: 8)).foregroundColor(.white), at: glyph.point)
            }
        }
        // Selected text owns priority; other labels share one bounded collision budget.
        scene.labelBounds.removeAll(keepingCapacity: true)
        for index in scene.labelPriority where scene.labelBounds.count < 32 {
            let glyph = scene.glyphs[index]
            let selected = glyph.node.id == state.selectedNodeID
            guard selected || glyph.node.isHighlighted || glyph.radius >= 5 else { continue }
            let text = context.resolve(Text(glyph.node.label).font(.system(size: 10, weight: selected ? .semibold : .regular)))
            let measured = text.measure(in: CGSize(width: 180, height: 30))
            let point = CGPoint(x: glyph.point.x, y: glyph.point.y + glyph.radius + 8)
            let bounds = CGRect(x: point.x - measured.width / 2, y: point.y - measured.height / 2,
                                width: measured.width, height: measured.height).insetBy(dx: -3, dy: -2)
            guard selected || !scene.labelBounds.contains(where: { $0.intersects(bounds) }) else { continue }
            scene.labelBounds.append(bounds)
            context.draw(text, at: point)
        }
        for label in scene.edgeLabels {
            context.draw(Text(label.text).font(.system(size: 9)).foregroundColor(.secondary), at: label.point)
        }
    }
}
