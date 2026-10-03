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
        .task(id: state.spatialDocumentRevision) { await state.prepareSpatialLayout() }
        .onDisappear { state.cancelSpatialLayout() }
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
            state.spatialCamera.orbit(dx: x, dy: y, roll: roll)
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
                    .accessibilityLabel("Relationship network. Three-finger drag to orbit and twist to roll. Mouse drag to orbit, scroll to pan, pinch to zoom. Option-drag moves a display point.")
            }
        }
        .overlay(alignment: .bottomLeading) {
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
                      nodes: state.visibleNodes, selectedID: state.selectedNodeID, size: size)
    }

    private func draw(context: inout GraphicsContext, layout: GraphSpatialLayout, size: CGSize) {
        project(layout: layout, size: size)
        let colors = state.nodeColorMap
        let icons = state.nodeIconMap
        context.stroke(scene.normalPath, with: .color(.primary.opacity(0.10)), lineWidth: 0.5)
        context.stroke(scene.emphasizedPath, with: .color(.primary.opacity(0.55)), lineWidth: 0.8)
        context.stroke(scene.arrowPath, with: .color(.primary.opacity(0.7)), lineWidth: 0.8)
        for glyph in scene.glyphs {
            let selected = glyph.node.id == state.selectedNodeID
            let style = GraphNodeStyle.style(for: glyph.node.role)
            let color = state.mapping.nodeColor(for: glyph.node, baseColor: colors[glyph.node.id] ?? style.color)
            let shape = glyph.node.role == .type
                ? Path(roundedRect: glyph.rect, cornerRadius: min(2, glyph.radius / 3)) : Path(ellipseIn: glyph.rect)
            context.fill(shape, with: .color(color.opacity(selected ? 1 : 0.7)))
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
