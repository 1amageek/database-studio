import SwiftUI

/// エッジ描画 + ノード配置のキャンバス（全描画を Canvas で実行）
///
/// embedding-atlas (apple/embedding-atlas) の最適化パターンを適用:
/// - **Viewport culling**: 可視領域外のノード/エッジを描画スキップ
/// - **Level of Detail**: ズームレベルに応じた描画詳細度の段階的変更
/// - **Edge batching**: 低 LOD で非ハイライトエッジを単一 Path にバッチ
/// - **Pre-computed screen positions**: ワールド→スクリーン座標変換を1回だけ実行
struct GraphCanvas: View {
    @Bindable var state: GraphViewState

    @State private var draggingNodeID: String?

    var body: some View {
        // layoutVersion を読むことで、ForceDirectedLayout の位置更新時に
        // Canvas が再描画される（ForceDirectedLayout は @Observable ではない）
        let _ = state.layoutVersion

        GeometryReader { geometry in
            let size = geometry.size

            CanvasHostView(
                onScroll: { dx, dy in
                    state.markUserAdjustedCamera()
                    state.cameraOffset.width += dx
                    state.cameraOffset.height += dy
                },
                onMagnify: { delta, cursorPoint in
                    state.markUserAdjustedCamera()
                    let oldScale = state.cameraScale
                    let newScale = max(0.05, min(5.0, oldScale * (1 + delta)))
                    let ratio = newScale / oldScale
                    state.cameraOffset = CGSize(
                        width: cursorPoint.x - (cursorPoint.x - state.cameraOffset.width) * ratio,
                        height: cursorPoint.y - (cursorPoint.y - state.cameraOffset.height) * ratio
                    )
                    state.cameraScale = newScale
                }
            ) {
                // スナップショットを body 評価時に1回だけ取得
                let visibleEdges = state.visibleEdges
                let visibleNodes = state.visibleNodes
                let highlightedEdges = state.mapping.highlightedEdges
                let highlightedPath = state.mapping.highlightedPath
                let searchMatched = state.searchMatchedNodeIDs
                let isSearchActive = state.isSearchActive
                let cameraScale = state.cameraScale
                let cameraOffset = state.cameraOffset
                let selectedNodeID = state.selectedNodeID
                let mapping = state.mapping
                let nodeIconMap = state.nodeIconMap
                let nodeColorMap = state.nodeColorMap

                // ノード半径キャッシュ（選択ノードは1.6倍）
                let nodeRadiusMap: [String: CGFloat] = {
                    var m: [String: CGFloat] = [:]
                    m.reserveCapacity(visibleNodes.count)
                    for node in visibleNodes {
                        let style = GraphNodeStyle.style(for: node.kind)
                        var radius = mapping.nodeRadius(for: node, baseRadius: style.radius)
                        if node.id == selectedNodeID {
                            radius *= 1.6
                        }
                        m[node.id] = radius
                    }
                    return m
                }()

                // Pre-computed screen positions（embedding-atlas pattern: 座標変換は1回だけ）
                let layoutPositions = state.activeLayout.positions
                let screenPositions: [String: CGPoint] = {
                    var sp: [String: CGPoint] = [:]
                    sp.reserveCapacity(layoutPositions.count)
                    for (id, pos) in layoutPositions {
                        sp[id] = CGPoint(
                            x: pos.x * cameraScale + cameraOffset.width,
                            y: pos.y * cameraScale + cameraOffset.height
                        )
                    }
                    return sp
                }()

                // EdgeCurvatureMap は LOD 2 以上でのみ必要
                let edgeCurvatures: EdgeCurvatureMap? = cameraScale >= 0.15
                    ? EdgeCurvatureMap(edges: visibleEdges) : nil

                Canvas { context, canvasSize in
                    let scale = cameraScale

                    // --- Viewport culling bounds（余白付き） ---
                    let margin: CGFloat = 80
                    let viewMinX = -margin
                    let viewMinY = -margin
                    let viewMaxX = canvasSize.width + margin
                    let viewMaxY = canvasSize.height + margin

                    // --- LOD (embedding-atlas style: ズームに応じた描画詳細度) ---
                    //
                    // LOD 0 (scale < 0.08): ドットのみ、エッジなし
                    // LOD 1 (scale < 0.15): バッチ直線 + 小ドット
                    // LOD 2 (scale < 0.3):  ベジェ + 矢印 + 着色円（テキストなし）
                    // LOD 3 (scale >= 0.3): フル詳細（アイコン、ラベル、エッジラベル）
                    let lod: Int
                    if scale < 0.08 { lod = 0 }
                    else if scale < 0.15 { lod = 1 }
                    else if scale < 0.3 { lod = 2 }
                    else { lod = 3 }

                    // ============================
                    // エッジ描画
                    // ============================
                    if lod == 1 {
                        // LOD 1: 全エッジを直線でバッチ描画（個別 stroke を回避）
                        var batchPath = SwiftUI.Path()
                        var hlPath = SwiftUI.Path()

                        for edge in visibleEdges {
                            guard let src = screenPositions[edge.sourceID],
                                  let tgt = screenPositions[edge.targetID] else { continue }

                            // Viewport cull: 両端点が同じ側の外にあればスキップ
                            if (src.x < viewMinX && tgt.x < viewMinX) ||
                               (src.x > viewMaxX && tgt.x > viewMaxX) ||
                               (src.y < viewMinY && tgt.y < viewMinY) ||
                               (src.y > viewMaxY && tgt.y > viewMaxY) { continue }

                            let isHL = edge.isHighlighted || highlightedEdges.contains(edge.id)
                            if isHL {
                                hlPath.move(to: src)
                                hlPath.addLine(to: tgt)
                            } else {
                                batchPath.move(to: src)
                                batchPath.addLine(to: tgt)
                            }
                        }

                        context.stroke(batchPath, with: .color(Color.secondary.opacity(0.25)), lineWidth: 0.5)
                        if !hlPath.isEmpty {
                            context.stroke(hlPath, with: .color(Color.accentColor.opacity(0.8)), lineWidth: 2)
                        }
                    } else if lod >= 2 {
                        // LOD 2-3: 個別ベジェエッジ + 矢印
                        for edge in visibleEdges {
                            guard let src = screenPositions[edge.sourceID],
                                  let tgt = screenPositions[edge.targetID] else { continue }

                            // Viewport cull
                            if (src.x < viewMinX && tgt.x < viewMinX) ||
                               (src.x > viewMaxX && tgt.x > viewMaxX) ||
                               (src.y < viewMinY && tgt.y < viewMinY) ||
                               (src.y > viewMaxY && tgt.y > viewMaxY) { continue }

                            let curvature = edgeCurvatures?.curvature(for: edge.id) ?? 0
                            let isHighlighted = edge.isHighlighted || highlightedEdges.contains(edge.id)
                            let control = Self.controlPoint(from: src, to: tgt, curvature: curvature)

                            var bezierPath = SwiftUI.Path()
                            bezierPath.move(to: src)
                            bezierPath.addQuadCurve(to: tgt, control: control)

                            let edgeColor: Color = isHighlighted ? .accentColor : .secondary
                            let edgeOpacity: Double = isHighlighted ? 0.9 : 0.5
                            let lineWidth: CGFloat = isHighlighted ? 2.5 : 1

                            context.stroke(bezierPath, with: .color(edgeColor.opacity(edgeOpacity)), lineWidth: lineWidth)

                            // 矢印
                            let targetRadius = (nodeRadiusMap[edge.targetID] ?? 24) * min(scale, 1.0)
                            let arrowPath = Self.arrowHead(
                                from: src, to: tgt, control: control,
                                targetRadius: targetRadius
                            )
                            context.fill(arrowPath, with: .color(edgeColor.opacity(edgeOpacity + 0.1)))

                            // エッジラベル（LOD 3 のみ — Text 生成はコストが高い）
                            if lod >= 3 {
                                let mid = Self.quadBezier(from: src, to: tgt, control: control, t: 0.5)
                                // カーブの接線方向から法線を求め、ラベルをカーブの外側にオフセット
                                let tangent = Self.quadBezierTangent(from: src, to: tgt, control: control, t: 0.5)
                                let tLen = sqrt(tangent.x * tangent.x + tangent.y * tangent.y)
                                let labelOffset: CGFloat = 12
                                let labelPos: CGPoint
                                if tLen > 0 {
                                    // 法線（左側）= (-ty, tx) / len
                                    let nx = -tangent.y / tLen
                                    let ny = tangent.x / tLen
                                    // curvature の符号に合わせてラベルをカーブの外側に配置
                                    let sign: CGFloat = curvature >= 0 ? -1 : 1
                                    labelPos = CGPoint(x: mid.x + nx * labelOffset * sign, y: mid.y + ny * labelOffset * sign)
                                } else {
                                    labelPos = CGPoint(x: mid.x, y: mid.y - labelOffset)
                                }
                                let text = Text(edge.label)
                                    .font(.system(size: 10))
                                    .foregroundColor(isHighlighted ? .accentColor.opacity(0.8) : .secondary.opacity(0.4))
                                context.draw(text, at: labelPos)
                            }
                        }
                    }
                    // LOD 0: エッジ描画なし

                    // ============================
                    // ノード描画
                    // ============================
                    if lod <= 1 {
                        // LOD 0-1: シンプルなドット（Text 生成ゼロ）
                        let dotRadius: CGFloat = lod == 0 ? 2 : 3

                        for node in visibleNodes {
                            guard let center = screenPositions[node.id] else { continue }

                            // Viewport cull
                            if center.x < viewMinX || center.x > viewMaxX ||
                               center.y < viewMinY || center.y > viewMaxY { continue }

                            let style = GraphNodeStyle.style(for: node.kind)
                            let baseColor = nodeColorMap[node.id] ?? style.color
                            let color = mapping.nodeColor(for: node, defaultColor: baseColor)
                            let isHL = node.isHighlighted || highlightedPath.contains(node.id)
                            let isDimmed = isSearchActive && !searchMatched.contains(node.id)
                            let opacity: Double = isDimmed ? 0.15 : 1.0

                            let r = isHL ? dotRadius * 1.5 : dotRadius
                            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                            context.fill(SwiftUI.Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
                        }
                    } else {
                        // LOD 2-3: 着色円 + ストローク（+ テキスト @ LOD 3）
                        let nodeScale = min(scale, 1.0)

                        for node in visibleNodes {
                            guard let center = screenPositions[node.id] else { continue }

                            let style = GraphNodeStyle.style(for: node.kind)
                            let radius = (nodeRadiusMap[node.id] ?? style.radius) * nodeScale

                            // Viewport cull（ラベル分の余白を考慮）
                            let cullMargin = radius + (lod >= 3 ? 30 : 0)
                            if center.x + cullMargin < viewMinX || center.x - cullMargin > viewMaxX ||
                               center.y + cullMargin < viewMinY || center.y - cullMargin > viewMaxY { continue }

                            let baseColor = nodeColorMap[node.id] ?? style.color
                            let color = mapping.nodeColor(for: node, defaultColor: baseColor)
                            let isSelected = selectedNodeID == node.id
                            let isHighlighted = node.isHighlighted || highlightedPath.contains(node.id)
                            let isMatched = searchMatched.contains(node.id)
                            let isDimmed = isSearchActive && !isMatched
                            let nodeOpacity: Double = isDimmed ? 0.15 : 1.0

                            // 塗りつぶし円（ソリッドカラー）
                            let circleRect = CGRect(
                                x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2
                            )
                            let circlePath = SwiftUI.Path(ellipseIn: circleRect)
                            context.fill(circlePath, with: .color(color.opacity(nodeOpacity)))

                            // ストローク
                            let strokeColor: Color = isMatched ? .yellow : (isSelected ? .white : color)
                            let strokeWidth: CGFloat = isMatched ? 3 : (isSelected ? 3 : (isHighlighted ? 2.5 : 0))
                            if strokeWidth > 0 {
                                context.stroke(circlePath, with: .color(strokeColor.opacity(nodeOpacity)), lineWidth: strokeWidth)
                            }

                            // アイコン（LOD 3 のみ — 白色・太ウェイトで描画）
                            if lod >= 3 {
                                let icon = nodeIconMap[node.id] ?? style.iconName
                                let iconText = Text(Image(systemName: icon))
                                    .font(.system(size: radius * 0.7, weight: .bold))
                                    .foregroundColor(.white.opacity(nodeOpacity))
                                context.draw(iconText, at: center)
                            }

                            // ラベル（LOD 3 のみ、選択ノードは太字・大きめ）
                            if lod >= 3 {
                                let labelColor: Color = isMatched ? .yellow : .primary
                                let fontSize: CGFloat = isSelected ? 13 : 11
                                let fontWeight: Font.Weight = isSelected ? .bold : .regular
                                let label = Text(node.label)
                                    .font(.system(size: fontSize, weight: fontWeight))
                                    .foregroundColor(labelColor.opacity(nodeOpacity))
                                context.draw(label, at: CGPoint(x: center.x, y: center.y + radius + 10))
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if draggingNodeID == nil {
                                draggingNodeID = hitTestNode(
                                    at: value.startLocation,
                                    nodes: visibleNodes,
                                    radiusMap: nodeRadiusMap,
                                    screenPositions: screenPositions,
                                    scale: cameraScale
                                )
                            }
                            if let nodeID = draggingNodeID {
                                let raw = inverseTransform(value.location, scale: cameraScale, offset: cameraOffset)
                                state.activeLayout.pin(nodeID, at: raw)
                                state.bumpLayoutVersion()
                            }
                        }
                        .onEnded { _ in
                            if let nodeID = draggingNodeID {
                                state.activeLayout.unpin(nodeID)
                                state.resumeSimulation(size: size)
                            }
                            draggingNodeID = nil
                        }
                )
                .onTapGesture { location in
                    let tapped = hitTestNode(
                        at: location,
                        nodes: visibleNodes,
                        radiusMap: nodeRadiusMap,
                        screenPositions: screenPositions,
                        scale: cameraScale
                    )
                    state.selectNode(state.selectedNodeID == tapped ? nil : tapped)
                }
            }
            .contextMenu {
                backgroundContextMenu
            }
            .onAppear {
                state.handleViewportChange(from: .zero, to: size)
            }
            .onChange(of: size) { oldSize, newSize in
                state.handleViewportChange(from: oldSize, to: newSize)
            }
            .onDisappear {
                state.stopSimulation()
            }
        }
    }

    // MARK: - Hit Test

    /// Pre-computed screen positions を使ったヒットテスト
    private func hitTestNode(
        at point: CGPoint,
        nodes: [GraphNode],
        radiusMap: [String: CGFloat],
        screenPositions: [String: CGPoint],
        scale: CGFloat
    ) -> String? {
        let nodeScale = min(scale, 1.0)
        for node in nodes.reversed() {
            guard let center = screenPositions[node.id] else { continue }
            let radius = (radiusMap[node.id] ?? 24) * nodeScale
            let dx = point.x - center.x
            let dy = point.y - center.y
            if dx * dx + dy * dy <= radius * radius {
                return node.id
            }
        }
        return nil
    }

    private func inverseTransform(_ point: CGPoint, scale: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - offset.width) / scale,
            y: (point.y - offset.height) / scale
        )
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var backgroundContextMenu: some View {
        Button("Zoom to Fit") {
            state.zoomToFit()
        }
        Button("Clear Selection") {
            state.selectNode(nil)
        }
        Button("Clear Highlights") {
            state.mapping.highlightedPath.removeAll()
            state.mapping.highlightedEdges.removeAll()
        }
    }

    // MARK: - 静的ジオメトリ計算

    private static func controlPoint(from source: CGPoint, to target: CGPoint, curvature: CGFloat) -> CGPoint {
        let midX = (source.x + target.x) / 2
        let midY = (source.y + target.y) / 2
        let dx = target.x - source.x
        let dy = target.y - source.y
        return CGPoint(x: midX - dy * curvature, y: midY + dx * curvature)
    }

    private static func quadBezier(from p0: CGPoint, to p2: CGPoint, control p1: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
            y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
        )
    }

    /// 二次ベジェ曲線の t における接線ベクトル
    private static func quadBezierTangent(from p0: CGPoint, to p2: CGPoint, control p1: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: 2 * u * (p1.x - p0.x) + 2 * t * (p2.x - p1.x),
            y: 2 * u * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
        )
    }

    private static func arrowHead(
        from source: CGPoint, to target: CGPoint, control: CGPoint,
        targetRadius: CGFloat
    ) -> SwiftUI.Path {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > targetRadius * 2 else { return SwiftUI.Path() }

        let approxT: CGFloat = 1.0 - targetRadius / length
        let tip = quadBezier(from: source, to: target, control: control, t: approxT)
        let back = quadBezier(from: source, to: target, control: control, t: approxT - 0.05)

        let adx = tip.x - back.x
        let ady = tip.y - back.y
        let adist = sqrt(adx * adx + ady * ady)
        guard adist > 0 else { return SwiftUI.Path() }

        let ux = adx / adist
        let uy = ady / adist
        let arrowLength: CGFloat = 6
        let arrowWidth: CGFloat = 3
        let baseX = tip.x - ux * arrowLength
        let baseY = tip.y - uy * arrowLength

        var path = SwiftUI.Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: baseX + uy * arrowWidth, y: baseY - ux * arrowWidth))
        path.addLine(to: CGPoint(x: baseX - uy * arrowWidth, y: baseY + ux * arrowWidth))
        path.closeSubpath()
        return path
    }
}

// MARK: - EdgeCurvatureMap

private struct EdgeCurvatureMap {
    private let curvatures: [String: CGFloat]

    init(edges: [GraphEdge]) {
        var groups: [String: [String]] = [:]
        for edge in edges {
            let pairKey = Self.pairKey(edge.sourceID, edge.targetID)
            groups[pairKey, default: []].append(edge.id)
        }

        var result: [String: CGFloat] = [:]
        result.reserveCapacity(edges.count)
        for (_, edgeIDs) in groups {
            if edgeIDs.count == 1 {
                result[edgeIDs[0]] = 0
            } else {
                for (i, edgeID) in edgeIDs.enumerated() {
                    let level = CGFloat((i / 2) + 1) * 0.4
                    let sign: CGFloat = i.isMultiple(of: 2) ? -1 : 1
                    result[edgeID] = sign * level
                }
            }
        }
        self.curvatures = result
    }

    func curvature(for edgeID: String) -> CGFloat {
        curvatures[edgeID] ?? 0
    }

    private static func pairKey(_ a: String, _ b: String) -> String {
        a < b ? "\(a)⟷\(b)" : "\(b)⟷\(a)"
    }
}
