import SwiftUI
import RealityKit
import Metal

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
            } else if MTLCreateSystemDefaultDevice() == nil {
                unavailable("3D graphics are unavailable on this Mac.")
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
        }, onMagnify: { delta, _ in state.spatialCamera.zoom(delta) }) {
            ZStack {
                RealityView { content in
                    content.add(scene.root)
                    updateScene(layout)
                } update: { _ in updateScene(layout) }
                .allowsHitTesting(false)
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
                    .accessibilityLabel("Relationship network. Drag to orbit, scroll to pan, pinch to zoom. Option-drag moves a display point.")
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
                Text("Drag to orbit · Option-drag to arrange")
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

    private func updateScene(_ layout: GraphSpatialLayout) {
        do {
            try scene.update(camera: state.spatialCamera, layout: layout, revision: state.spatialGeometryRevision,
                             edges: state.visibleEdges, selectedID: state.selectedNodeID, dark: colorScheme == .dark)
        } catch { state.reportSpatialFailure(error) }
    }

    private func project(layout: GraphSpatialLayout, size: CGSize) {
        scene.project(camera: state.spatialCamera, layout: layout, revision: state.spatialGeometryRevision,
                      nodes: state.visibleNodes, selectedID: state.selectedNodeID, size: size)
    }

    private func draw(context: inout GraphicsContext, layout: GraphSpatialLayout, size: CGSize) {
        project(layout: layout, size: size)
        let colors = state.nodeColorMap
        let icons = state.nodeIconMap
        for edge in state.visibleEdges {
            guard let source = scene.glyphIndices[edge.sourceID], let target = scene.glyphIndices[edge.targetID] else { continue }
            let start = scene.glyphs[source].point
            let end = scene.glyphs[target].point
            let selected = state.selectedNodeID == edge.sourceID || state.selectedNodeID == edge.targetID
            if edge.sourceID == edge.targetID {
                let loop = CGRect(x: start.x - 12, y: start.y - 23, width: 24, height: 24)
                context.stroke(Path(ellipseIn: loop), with: .color(.primary.opacity(selected ? 0.6 : 0.15)), lineWidth: 0.7)
            }
            guard selected else { continue }
            let length = hypot(end.x - start.x, end.y - start.y)
            if length > 20 {
                let ux = (end.x - start.x) / length, uy = (end.y - start.y) / length
                let radius = scene.glyphs[target].radius + 3
                let tip = CGPoint(x: end.x - ux * radius, y: end.y - uy * radius)
                var arrow = Path()
                arrow.move(to: CGPoint(x: tip.x - ux * 5 - uy * 2, y: tip.y - uy * 5 + ux * 2))
                arrow.addLine(to: tip)
                arrow.addLine(to: CGPoint(x: tip.x - ux * 5 + uy * 2, y: tip.y - uy * 5 - ux * 2))
                context.stroke(arrow, with: .color(.primary.opacity(0.7)), lineWidth: 0.8)
            }
        }
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
        if let selected = state.selectedNodeID {
            var count = 0
            for edge in state.visibleEdges where edge.sourceID == selected || edge.targetID == selected {
                guard count < 32 else { break }
                guard let source = scene.glyphIndices[edge.sourceID], let target = scene.glyphIndices[edge.targetID] else { continue }
                let start = scene.glyphs[source].point, end = scene.glyphs[target].point
                count += 1
                context.draw(Text(edge.label).font(.system(size: 9)).foregroundColor(.secondary),
                             at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 7))
            }
        }
    }
}
