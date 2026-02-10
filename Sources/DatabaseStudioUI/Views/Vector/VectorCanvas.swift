import SwiftUI

/// ベクトル空間の2D散布図（Canvas 描画）
struct VectorCanvas: View {
    @Bindable var state: VectorViewState

    @State private var dragStartOffset: CGSize = .zero
    @State private var draggedPointID: String?
    @State private var hasInitialFit = false

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let scale = state.cameraScale
                let offset = state.cameraOffset

                let visibleRect = CGRect(
                    x: -offset.width / scale - 80 / scale,
                    y: -offset.height / scale - 80 / scale,
                    width: size.width / scale + 160 / scale,
                    height: size.height / scale + 160 / scale
                )

                // KNN 接続線
                if let selected = state.selectedPoint {
                    let selectedScreen = screenPosition(selected.projected, scale: scale, offset: offset)
                    for result in state.knnResults {
                        let targetScreen = screenPosition(result.point.projected, scale: scale, offset: offset)
                        var path = Path()
                        path.move(to: selectedScreen)
                        path.addLine(to: targetScreen)
                        context.stroke(path, with: .color(.blue.opacity(0.2)), lineWidth: 1)
                    }
                }

                // ポイント描画
                for point in state.projectedPoints {
                    let pos = point.projected
                    guard visibleRect.contains(pos) else { continue }

                    let screen = screenPosition(pos, scale: scale, offset: offset)
                    let isSelected = state.selectedPointID == point.id
                    let isKNNResult = state.knnResultIDs.contains(point.id)

                    let radius = state.radius(for: point) * (isSelected ? 1.8 : 1.0)
                    let color = state.color(for: point)

                    // ドット
                    let circle = Path(ellipseIn: CGRect(
                        x: screen.x - radius,
                        y: screen.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))

                    if isSelected {
                        context.fill(circle, with: .color(.red))
                        // 選択リング
                        let ring = Path(ellipseIn: CGRect(
                            x: screen.x - radius - 3,
                            y: screen.y - radius - 3,
                            width: (radius + 3) * 2,
                            height: (radius + 3) * 2
                        ))
                        context.stroke(ring, with: .color(.red), lineWidth: 2)
                    } else if isKNNResult {
                        context.fill(circle, with: .color(.green))
                    } else {
                        context.fill(circle, with: .color(color.opacity(0.7)))
                    }

                    // ラベル（ズームレベル十分な場合のみ）
                    if state.showLabels && scale >= 0.8 {
                        let text = Text(point.label)
                            .font(.system(size: 9))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                        context.draw(
                            context.resolve(text),
                            at: CGPoint(x: screen.x, y: screen.y + radius + 8)
                        )
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartOffset == .zero {
                            dragStartOffset = state.cameraOffset
                        }
                        state.cameraOffset = CGSize(
                            width: dragStartOffset.width + value.translation.width,
                            height: dragStartOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        dragStartOffset = .zero
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let newScale = state.cameraScale * value.magnification
                        state.cameraScale = min(max(newScale, 0.05), 10.0)
                    }
            )
            .onTapGesture { location in
                handleTap(at: location)
            }
            .onAppear {
                state.viewportSize = geo.size
                if !hasInitialFit {
                    hasInitialFit = true
                    DispatchQueue.main.async {
                        state.zoomToFit()
                    }
                }
            }
            .onChange(of: geo.size) { _, newSize in
                state.viewportSize = newSize
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 座標変換

    private func screenPosition(_ point: CGPoint, scale: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(
            x: point.x * scale + offset.width,
            y: point.y * scale + offset.height
        )
    }

    // MARK: - タップ処理

    private func handleTap(at location: CGPoint) {
        let scale = state.cameraScale
        let offset = state.cameraOffset
        let hitRadius: CGFloat = 12.0

        var closest: (id: String, dist: CGFloat)?

        for point in state.projectedPoints {
            let screen = screenPosition(point.projected, scale: scale, offset: offset)
            let dx = location.x - screen.x
            let dy = location.y - screen.y
            let dist = sqrt(dx * dx + dy * dy)

            if dist < hitRadius {
                if closest == nil || dist < closest!.dist {
                    closest = (point.id, dist)
                }
            }
        }

        state.selectedPointID = closest?.id
    }
}
