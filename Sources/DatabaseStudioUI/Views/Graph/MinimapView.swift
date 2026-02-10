import SwiftUI

/// Cytoscape 風ミニマップオーバーレイ
struct MinimapView: View {
    let state: GraphViewState
    let width: CGFloat = 150
    let height: CGFloat = 100

    var body: some View {
        let nodes = state.visibleNodes
        let positions = nodes.compactMap { node -> (id: String, pos: CGPoint)? in
            guard let pos = state.activeLayout.positions[node.id] else { return nil }
            return (node.id, CGPoint(x: pos.x, y: pos.y))
        }

        Canvas { context, size in
            guard !positions.isEmpty else { return }

            let xs = positions.map(\.pos.x)
            let ys = positions.map(\.pos.y)
            let minX = xs.min()!
            let maxX = xs.max()!
            let minY = ys.min()!
            let maxY = ys.max()!

            let graphWidth = max(maxX - minX, 1)
            let graphHeight = max(maxY - minY, 1)

            let padding: CGFloat = 10
            let drawW = size.width - padding * 2
            let drawH = size.height - padding * 2
            let scale = min(drawW / graphWidth, drawH / graphHeight)

            let offsetX = padding + (drawW - graphWidth * scale) / 2
            let offsetY = padding + (drawH - graphHeight * scale) / 2

            // ノードをドットで描画（プリミティブクラス色を反映）
            let colorMap = state.nodeColorMap
            for (id, pos) in positions {
                let x = (pos.x - minX) * scale + offsetX
                let y = (pos.y - minY) * scale + offsetY
                let node = nodes.first { $0.id == id }
                let style = node.map { GraphNodeStyle.style(for: $0.kind) }
                let color = colorMap[id] ?? style?.color ?? .gray
                let dotSize: CGFloat = 3
                let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Circle().path(in: rect), with: .color(color))
            }

            // 現在のビューポート矩形
            guard state.viewportSize.width > 0, state.cameraScale > 0 else { return }

            let vpLeft = (0 - state.cameraOffset.width) / state.cameraScale
            let vpTop = (0 - state.cameraOffset.height) / state.cameraScale
            let vpWidth = state.viewportSize.width / state.cameraScale
            let vpHeight = state.viewportSize.height / state.cameraScale

            let rectX = (vpLeft - minX) * scale + offsetX
            let rectY = (vpTop - minY) * scale + offsetY
            let rectW = vpWidth * scale
            let rectH = vpHeight * scale

            let vpRect = CGRect(x: rectX, y: rectY, width: rectW, height: rectH)
            context.stroke(
                RoundedRectangle(cornerRadius: 2).path(in: vpRect),
                with: .color(.accentColor.opacity(0.8)),
                lineWidth: 1.5
            )
        }
        .frame(width: width, height: height)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }
}
