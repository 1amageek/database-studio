import SwiftUI

enum TimelineOrientation: String, CaseIterable, Sendable {
    case off = "Off"
    case horizontal = "Horizontal"
    case vertical = "Vertical"
}

/// グラフ可視化の状態管理
@Observable @MainActor
final class GraphViewState {

    // MARK: - データ

    var document: GraphDocument {
        didSet { invalidateCache() }
    }

    /// フルグラフ用レイアウト（サーチ中も位置を保持）
    let fullLayout: ForceDirectedLayout = ForceDirectedLayout()

    /// サーチフィルタ用レイアウト（独立インスタンス）
    let focusLayout: ForceDirectedLayout = ForceDirectedLayout()

    /// フォーカスモード判定（ノード選択 or 検索でサブセット表示中）
    var isFocusMode: Bool {
        (selectedNodeID != nil && focusHops > 0) || isSearchActive
    }

    /// 現在アクティブなレイアウト（フォーカスモード中は focusLayout）
    var activeLayout: ForceDirectedLayout {
        isFocusMode ? focusLayout : fullLayout
    }

    // MARK: - ビジュアルマッピング

    var mapping: GraphVisualMapping = GraphVisualMapping()

    // MARK: - クラスノード表示

    /// クラス（.type）ノードをグラフに表示するか
    var showClassNodes: Bool = false {
        didSet { invalidateVisibleCache() }
    }

    // MARK: - タイムラインレイアウト

    /// タイムライン配置モード（off / horizontal / vertical）
    var timelineOrientation: TimelineOrientation = .off {
        didSet {
            guard oldValue != timelineOrientation else { return }
            applyTimelineLayout()
        }
    }

    /// タイムライン上の Event ノード目標位置キャッシュ
    private var cachedTimelinePositions: [String: CGPoint]?

    /// タイムライン上に配置された Event ノード ID（Canvas のラベル表示用）
    var timelineEventNodeIDs: Set<String> {
        guard timelineOrientation != .off else { return [] }
        guard let cached = cachedTimelinePositions else { return [] }
        return Set(cached.keys)
    }

    // MARK: - Backbone

    /// Backbone モードが有効か（大規模グラフの初期表示で代表ノードのみ表示）
    var isBackboneActive: Bool = false {
        didSet { invalidateVisibleCache() }
    }

    private var cachedMetrics: GraphMetricsComputer.Result?
    private var cachedBackboneNodeIDs: Set<String>?

    /// Backbone ノード ID（キャッシュ済み）
    var backboneNodeIDs: Set<String> {
        if let cached = cachedBackboneNodeIDs { return cached }
        let metrics = computedMetrics
        let result = GraphBackbone.selectBackboneNodes(document: document, metrics: metrics)
        cachedBackboneNodeIDs = result
        return result
    }

    /// 計算済みメトリクス（キャッシュ済み）
    var computedMetrics: GraphMetricsComputer.Result {
        if let cached = cachedMetrics { return cached }
        let result = GraphMetricsComputer.compute(document: document)
        cachedMetrics = result
        return result
    }

    /// グラフが backbone 表示可能な規模か
    var isBackboneAvailable: Bool { document.nodes.count >= 50 }

    // MARK: - 選択

    var selectedNodeID: String? {
        didSet {
            if timelineOrientation != .off {
                timelineOrientation = .off
            }
            invalidateVisibleCache()
            updateFocusLayout()
        }
    }

    var selectedNode: GraphNode? {
        guard let id = selectedNodeID else { return nil }
        return cachedNodeMap[id]
    }

    // MARK: - 選択履歴（ブラウザバック / フォワード）

    private var selectionHistory: [String] = []
    private var selectionHistoryIndex: Int = -1
    private var isNavigatingHistory = false

    var canGoBack: Bool { selectionHistoryIndex > 0 }
    var canGoForward: Bool { selectionHistoryIndex < selectionHistory.count - 1 }

    /// 履歴に新しい選択を記録する
    private func pushHistory(_ nodeID: String?) {
        guard !isNavigatingHistory else { return }
        guard let nodeID else {
            // nil 選択は履歴に入れない
            return
        }
        // 現在位置より先の履歴を切り捨て
        if selectionHistoryIndex < selectionHistory.count - 1 {
            selectionHistory.removeSubrange((selectionHistoryIndex + 1)...)
        }
        // 直前と同じなら追加しない
        if selectionHistory.last != nodeID {
            selectionHistory.append(nodeID)
        }
        selectionHistoryIndex = selectionHistory.count - 1
    }

    func goBack() {
        guard canGoBack else { return }
        isNavigatingHistory = true
        selectionHistoryIndex -= 1
        let nodeID = selectionHistory[selectionHistoryIndex]
        selectedNodeID = nodeID
        zoomToFit()
        isNavigatingHistory = false
    }

    func goForward() {
        guard canGoForward else { return }
        isNavigatingHistory = true
        selectionHistoryIndex += 1
        let nodeID = selectionHistory[selectionHistoryIndex]
        selectedNodeID = nodeID
        zoomToFit()
        isNavigatingHistory = false
    }

    // MARK: - N-hop 近傍フィルタ

    /// 選択ノードから何ホップの近傍を表示するか（0 = 全ノード表示）
    var focusHops: Int = 1 {
        didSet {
            invalidateVisibleCache()
            updateFocusLayout()
        }
    }

    private var cachedNeighborhoodNodeIDs: Set<String>?

    /// 選択ノードからの N-hop BFS で到達可能なノード ID を計算
    private func computeNeighborhood(from nodeID: String, hops: Int) -> Set<String> {
        // エッジラベルフィルタ適用済みのエッジを使用（subClassOf を除外: 親クラスは Inspector のみ）
        let filteredEdges = document.edges.filter {
            activeEdgeLabels.contains($0.label) && !Self.isSubClassOfLabel($0.label)
        }

        // 隣接リスト構築
        var adjacency: [String: [String]] = [:]
        for edge in filteredEdges {
            adjacency[edge.sourceID, default: []].append(edge.targetID)
            adjacency[edge.targetID, default: []].append(edge.sourceID)
        }

        // BFS
        var visited: Set<String> = [nodeID]
        var frontier: Set<String> = [nodeID]
        for _ in 0..<hops {
            var nextFrontier: Set<String> = []
            for id in frontier {
                for neighbor in adjacency[id] ?? [] {
                    if !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        nextFrontier.insert(neighbor)
                    }
                }
            }
            if nextFrontier.isEmpty { break }
            frontier = nextFrontier
        }
        return visited
    }

    /// 現在の近傍ノード ID（キャッシュ済み）
    var neighborhoodNodeIDs: Set<String>? {
        guard let nodeID = selectedNodeID, focusHops > 0 else { return nil }
        if let cached = cachedNeighborhoodNodeIDs { return cached }
        let result = computeNeighborhood(from: nodeID, hops: focusHops)
        cachedNeighborhoodNodeIDs = result
        return result
    }

    // MARK: - カメラ

    var cameraOffset: CGSize = .zero
    var cameraScale: CGFloat = 1.0
    var viewportSize: CGSize = .zero
    private var hasUserAdjustedCamera = false

    // MARK: - レイアウトバージョン（Canvas 再描画トリガー）

    /// ForceDirectedLayout は @Observable ではないため、
    /// 位置変更をこのカウンタで一括通知する。tick 毎に1回だけインクリメント。
    private(set) var layoutVersion: Int = 0

    /// ドラッグ中など、シミュレーション外で位置が変わった際に呼ぶ
    func bumpLayoutVersion() {
        layoutVersion &+= 1
    }

    // MARK: - 検索

    var searchText: String = "" {
        didSet {
            cachedSearchMatchedNodeIDs = nil
            invalidateVisibleCache()
            updateFocusLayout()
        }
    }

    /// フォーカスモードの切り替えに応じてレイアウトを更新
    private func updateFocusLayout() {
        if isFocusMode {
            enterFocusMode()
        } else {
            exitFocusMode()
        }
    }

    /// フォーカスモード突入: warmup で目標位置を計算 → 補間アニメーション
    private func enterFocusMode() {
        let nodeIDs = Array(visibleNodeIDs)
        guard !nodeIDs.isEmpty, viewportSize.width > 0 else { return }

        // 1. 現在の表示位置をキャプチャ
        var startPositions = fullLayout.positions
        for (id, pos) in focusLayout.positions {
            startPositions[id] = pos
        }

        // 2. 目標位置を warmup で事前計算（フレッシュな円周配置から収束させる）
        let simEdges = visibleEdges
        focusLayout.classNodeIDs = Set(document.nodes.filter { $0.role == .type }.map(\.id))
        focusLayout.initialize(nodeIDs: nodeIDs, size: viewportSize)
        focusLayout.restart()
        focusLayout.warmup(nodeIDs: nodeIDs, edges: simEdges, size: viewportSize)
        let targetPositions = focusLayout.positions

        // 3. 補間アニメーション（embedding-atlas パターン）
        animateLayoutTransition(
            from: startPositions,
            to: targetPositions,
            layout: focusLayout
        )
    }

    /// フォーカスモード解除: fullLayout の既存位置へ補間アニメーション
    private func exitFocusMode() {
        let startPositions = focusLayout.positions
        let targetPositions = fullLayout.positions

        animateLayoutTransition(
            from: startPositions,
            to: targetPositions,
            layout: fullLayout
        )
    }

    // MARK: - レイアウト遷移アニメーション (embedding-atlas inspired)

    /// 位置 + カメラを cubicOut easing で補間するアニメーションループ
    private func animateLayoutTransition(
        from startPositions: [String: NodePosition],
        to targetPositions: [String: NodePosition],
        layout: ForceDirectedLayout,
        duration: Double = 0.6
    ) {
        stopSimulation()

        // カメラの開始・目標状態をキャプチャ
        let startCamera = (offset: cameraOffset, scale: cameraScale)
        let targetCamera = computeCamera(for: targetPositions)

        let startTime = CFAbsoluteTimeGetCurrent()

        simulationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let rawT = min(elapsed / duration, 1.0)
                let t = cubicOut(rawT)

                // ノード位置を補間
                var interpolated: [String: NodePosition] = [:]
                for (id, target) in targetPositions {
                    let start = startPositions[id] ?? target
                    interpolated[id] = NodePosition(
                        x: mix(start.x, target.x, t),
                        y: mix(start.y, target.y, t)
                    )
                }
                layout.setPositions(interpolated)

                // カメラを補間（scale は log domain で自然なズーム）
                let logS0 = log(max(Double(startCamera.scale), 0.001))
                let logS1 = log(max(Double(targetCamera.scale), 0.001))
                self.cameraScale = CGFloat(exp(mix(logS0, logS1, t)))
                self.cameraOffset = CGSize(
                    width: CGFloat(mix(Double(startCamera.offset.width), Double(targetCamera.offset.width), t)),
                    height: CGFloat(mix(Double(startCamera.offset.height), Double(targetCamera.offset.height), t))
                )

                self.layoutVersion &+= 1

                if rawT >= 1.0 {
                    if self.viewportSize.width > 0, self.viewportSize.height > 0 {
                        self.resumeSimulation(size: self.viewportSize)
                    }
                    return
                }

                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
            }
        }
    }

    /// cubicOut easing: 高速スタート → 滑らかに減速
    private func cubicOut(_ t: Double) -> Double {
        let f = t - 1.0
        return f * f * f + 1.0
    }

    /// 線形補間
    private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// 外れ値の影響を抑えたバウンディングボックス
    private func robustBounds(for values: [NodePosition]) -> (minX: Double, maxX: Double, minY: Double, maxY: Double)? {
        let finite = values.filter { $0.x.isFinite && $0.y.isFinite }
        guard !finite.isEmpty else { return nil }

        var xs = finite.map(\.x)
        var ys = finite.map(\.y)
        xs.sort()
        ys.sort()

        if xs.count >= 50 {
            let trim = max(1, xs.count / 40) // 2.5%
            let low = trim
            let high = xs.count - 1 - trim
            if low < high {
                return (xs[low], xs[high], ys[low], ys[high])
            }
        }

        return (xs.first!, xs.last!, ys.first!, ys.last!)
    }

    /// 指定位置群に対する zoomToFit カメラ状態を計算（適用はしない）
    private func computeCamera(
        for positions: [String: NodePosition],
        padding: CGFloat = 60
    ) -> (offset: CGSize, scale: CGFloat) {
        let vals = Array(positions.values)
        guard !vals.isEmpty, viewportSize.width > 0, viewportSize.height > 0,
              let bounds = robustBounds(for: vals) else {
            return (offset: cameraOffset, scale: cameraScale)
        }
        let minX = bounds.minX
        let maxX = bounds.maxX
        let minY = bounds.minY
        let maxY = bounds.maxY

        let gw = maxX - minX
        let gh = maxY - minY
        let aw = Double(viewportSize.width) - Double(padding) * 2
        let ah = Double(viewportSize.height) - Double(padding) * 2
        guard aw > 1, ah > 1 else {
            return (offset: cameraOffset, scale: cameraScale)
        }

        let sx = gw > 0 ? aw / gw : 2.0
        let sy = gh > 0 ? ah / gh : 2.0
        let scale = CGFloat(max(0.08, min(sx, sy, 2.0)))

        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let offset = CGSize(
            width: viewportSize.width / 2 - CGFloat(cx) * scale,
            height: viewportSize.height / 2 - CGFloat(cy) * scale
        )
        return (offset: offset, scale: scale)
    }

    private var cachedSearchMatchedNodeIDs: Set<String>?

    var searchMatchedNodeIDs: Set<String> {
        if let cached = cachedSearchMatchedNodeIDs { return cached }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            cachedSearchMatchedNodeIDs = []
            return []
        }
        let result = Set(document.nodes.filter { node in
            if node.label.lowercased().contains(query) { return true }
            return node.metadata.values.contains { $0.lowercased().contains(query) }
        }.map(\.id))
        cachedSearchMatchedNodeIDs = result
        return result
    }

    var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - フィルター

    var activeEdgeLabels: Set<String> {
        didSet { invalidateVisibleCache() }
    }

    /// ファセットフィルタートークン（ファセット間 AND、ファセット内 OR）
    var filterTokens: [GraphFilterToken] = [] {
        didSet { invalidateVisibleCache() }
    }

    /// ドキュメント内の全エッジラベル（ソート済み）
    private var cachedAllEdgeLabels: [String]?
    var allEdgeLabels: [String] {
        if let cached = cachedAllEdgeLabels { return cached }
        let result = Array(Set(document.edges.map(\.label))).sorted()
        cachedAllEdgeLabels = result
        return result
    }

    /// 各ラベルのエッジ数（キャッシュ済み）
    private var cachedEdgeCounts: [String: Int]?
    func edgeCount(for label: String) -> Int {
        if cachedEdgeCounts == nil {
            var counts: [String: Int] = [:]
            for edge in document.edges {
                counts[edge.label, default: 0] += 1
            }
            cachedEdgeCounts = counts
        }
        return cachedEdgeCounts?[label] ?? 0
    }

    // MARK: - キャッシュ済みフィルター結果

    private var cachedVisibleEdges: [GraphEdge]?
    private var cachedVisibleNodes: [GraphNode]?
    private var cachedVisibleNodeIDs: Set<String>?
    private var cachedNodeMap: [String: GraphNode] = [:]

    /// フィルター適用後のエッジ（近傍フィルタ + ファセットフィルタ含む）
    var visibleEdges: [GraphEdge] {
        if let cached = cachedVisibleEdges { return cached }
        var result = document.edges.filter { activeEdgeLabels.contains($0.label) }
        // クラスノードフィルタ: showClassNodes が OFF かつ選択ノードが .type 以外の場合のみ除外
        let selectedIsType = selectedNodeID.flatMap({ cachedNodeMap[$0] })?.role == .type
        if !showClassNodes && !selectedIsType {
            let typeNodeIDs = Set(document.nodes.filter { $0.role == .type }.map(\.id))
            result = result.filter { !typeNodeIDs.contains($0.sourceID) && !typeNodeIDs.contains($0.targetID) }
        }
        // Backbone フィルタ: 両端が backbone ノードのエッジのみ
        if isBackboneActive && !isFocusMode && !isSearchActive {
            let backbone = backboneNodeIDs
            result = result.filter { backbone.contains($0.sourceID) && backbone.contains($0.targetID) }
        }
        // N-hop 近傍フィルタ: 選択ノードがある場合は近傍内のエッジのみ
        if let neighborhood = neighborhoodNodeIDs {
            result = result.filter { neighborhood.contains($0.sourceID) && neighborhood.contains($0.targetID) }
        }
        // サーチフィルタ: マッチしたノードに接続するエッジのみ
        if isSearchActive {
            let matched = searchMatchedNodeIDs
            result = result.filter { matched.contains($0.sourceID) || matched.contains($0.targetID) }
        }
        // ファセットフィルタートークン適用
        for token in filterTokens {
            if token.facet.isEdgeFacet {
                switch token.mode {
                case .include:
                    result = result.filter { token.facet.matchesEdge($0) }
                case .exclude:
                    result = result.filter { !token.facet.matchesEdge($0) }
                }
            }
            if token.facet.isNodeFacet {
                let types = nodeTypeMap
                switch token.mode {
                case .include:
                    result = result.filter { edge in
                        let srcMatch = cachedNodeMap[edge.sourceID].map { token.facet.matchesNode($0, nodeTypeMap: types) } ?? false
                        let tgtMatch = cachedNodeMap[edge.targetID].map { token.facet.matchesNode($0, nodeTypeMap: types) } ?? false
                        return srcMatch || tgtMatch
                    }
                case .exclude:
                    result = result.filter { edge in
                        let srcExclude = cachedNodeMap[edge.sourceID].map { token.facet.matchesNode($0, nodeTypeMap: types) } ?? false
                        let tgtExclude = cachedNodeMap[edge.targetID].map { token.facet.matchesNode($0, nodeTypeMap: types) } ?? false
                        return !srcExclude || !tgtExclude
                    }
                }
            }
        }
        cachedVisibleEdges = result
        return result
    }

    /// フィルター適用後のノード（表示中エッジに接続しているもの）
    var visibleNodes: [GraphNode] {
        if let cached = cachedVisibleNodes { return cached }
        let ids = visibleNodeIDs
        let result = document.nodes.filter { ids.contains($0.id) }
        cachedVisibleNodes = result
        return result
    }

    var visibleNodeIDs: Set<String> {
        if let cached = cachedVisibleNodeIDs { return cached }
        let edges = visibleEdges
        var ids = Set(edges.flatMap { [$0.sourceID, $0.targetID] })
        // 選択ノード自身は常に含める
        if let nodeID = selectedNodeID {
            ids.insert(nodeID)
        }
        // 孤立 backbone ノードも含める（他の backbone ノードと直接接続がなくても表示）
        if isBackboneActive && !isFocusMode && !isSearchActive {
            ids.formUnion(backboneNodeIDs)
        }
        // showClassNodes が OFF かつ選択ノードが .type 以外の場合のみ除外
        let selectedIsType = selectedNodeID.flatMap({ cachedNodeMap[$0] })?.role == .type
        if !showClassNodes && !selectedIsType {
            let typeNodeIDs = Set(document.nodes.filter { $0.role == .type }.map(\.id))
            ids.subtract(typeNodeIDs)
        }
        cachedVisibleNodeIDs = ids
        return ids
    }

    private func invalidateCache() {
        cachedAllEdgeLabels = nil
        cachedEdgeCounts = nil
        cachedNodeTypeMap = nil
        cachedSubClassOfMap = nil
        cachedNodeIconMap = nil
        cachedNodeColorMap = nil
        cachedClassTree = nil
        cachedOrphanClassNodes = nil
        cachedMetrics = nil
        cachedBackboneNodeIDs = nil
        cachedNodeMap = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })
        invalidateVisibleCache()
    }

    private func invalidateVisibleCache() {
        cachedVisibleEdges = nil
        cachedVisibleNodes = nil
        cachedVisibleNodeIDs = nil
        cachedNeighborhoodNodeIDs = nil
        cachedSearchMatchedNodeIDs = nil
        cachedNodeRadiusMap = nil
        cachedEdgeCurvatureMap = nil
    }

    // MARK: - nodeRadiusMap キャッシュ

    private var cachedNodeRadiusMap: [String: CGFloat]?
    private var cachedRadiusSelectedNodeID: String?
    private var cachedRadiusSizeMode: GraphVisualMapping.SizeMode?

    var nodeRadiusMap: [String: CGFloat] {
        if let cached = cachedNodeRadiusMap,
           cachedRadiusSelectedNodeID == selectedNodeID,
           cachedRadiusSizeMode == mapping.sizeMode {
            return cached
        }
        var m: [String: CGFloat] = [:]
        m.reserveCapacity(visibleNodes.count)
        for node in visibleNodes {
            let style = GraphNodeStyle.style(for: node.role)
            var radius = mapping.nodeRadius(for: node, baseRadius: style.radius)
            if node.id == selectedNodeID { radius *= 1.6 }
            m[node.id] = radius
        }
        cachedNodeRadiusMap = m
        cachedRadiusSelectedNodeID = selectedNodeID
        cachedRadiusSizeMode = mapping.sizeMode
        return m
    }

    // MARK: - EdgeCurvatureMap キャッシュ

    private var cachedEdgeCurvatureMap: EdgeCurvatureMap?

    var edgeCurvatureMap: EdgeCurvatureMap {
        if let cached = cachedEdgeCurvatureMap { return cached }
        let result = EdgeCurvatureMap(edges: visibleEdges)
        cachedEdgeCurvatureMap = result
        return result
    }

    // MARK: - クエリ

    var showQueryPanel = false
    var queryText: String = "SELECT ?s ?p ?o\nWHERE {\n  ?s ?p ?o\n}\nLIMIT 100"
    var queryResults: [QueryResultRow] = []
    var queryResultColumns: [String] = []
    var queryError: String?
    var isQueryExecuting = false
    var queryResultMode: QueryResultMode = .table

    var queryResultsRawText: String {
        guard !queryResults.isEmpty else { return "" }
        let columns = queryResultColumns
        var lines: [String] = [columns.joined(separator: "\t")]
        for row in queryResults {
            let values = columns.map { row.bindings[$0] ?? "" }
            lines.append(values.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    /// GraphDocument のインメモリデータに対して SPARQL クエリを実行
    func executeQuery() {
        isQueryExecuting = true
        queryError = nil
        queryResults = []
        queryResultColumns = []

        let doc = document
        let text = queryText

        Task {
            do {
                let store = InMemoryTripleStore(document: doc)
                let parsed = try SPARQLParser.parse(text)
                let evaluator = SPARQLEvaluator(store: store, prefixes: parsed.prefixes)
                let (columns, rows) = try evaluator.evaluate(parsed)
                self.queryResultColumns = columns
                self.queryResults = rows.map { QueryResultRow(bindings: $0) }
            } catch {
                self.queryError = error.localizedDescription
            }
            self.isQueryExecuting = false
        }
    }

    // MARK: - シミュレーション

    private var simulationTask: Task<Void, Never>?
    private var hasInitialFit = false

    // MARK: - 初期化

    init(document: GraphDocument) {
        let cleaned = document.removingOwlThing()
        let metrics = GraphMetricsComputer.compute(document: cleaned)
        var enriched = cleaned
        for i in enriched.nodes.indices {
            let id = enriched.nodes[i].id
            enriched.nodes[i].metrics["degree"] = metrics.degree[id] ?? 0
        }
        self.document = enriched
        self.cachedMetrics = metrics
        self.activeEdgeLabels = Set(enriched.edges.map(\.label))
        self.cachedNodeMap = Dictionary(uniqueKeysWithValues: enriched.nodes.map { ($0.id, $0) })
        self.isBackboneActive = enriched.nodes.count >= 50
    }

    // MARK: - ドキュメント更新

    func updateDocument(_ newDocument: GraphDocument) {
        let cleaned = newDocument.removingOwlThing()
        let previousNodeIDs = Set(document.nodes.map(\.id))

        // メトリクス計算 → ノードに設定
        let metrics = GraphMetricsComputer.compute(document: cleaned)
        var enriched = cleaned
        for i in enriched.nodes.indices {
            let id = enriched.nodes[i].id
            enriched.nodes[i].metrics["degree"] = metrics.degree[id] ?? 0
        }
        cachedMetrics = metrics
        cachedBackboneNodeIDs = nil

        document = enriched

        // 新しいエッジラベルを activeEdgeLabels に追加（既存のフィルタ状態は維持）
        let newLabels = Set(enriched.edges.map(\.label))
        let addedLabels = newLabels.subtracting(activeEdgeLabels.union(allEdgeLabels))
        activeEdgeLabels.formUnion(addedLabels)
        // 削除されたラベルを除去
        activeEdgeLabels = activeEdgeLabels.intersection(newLabels)

        // レイアウト更新: 新規ノード追加、削除ノード除去
        let newNodeIDs = Set(enriched.nodes.map(\.id))
        let addedNodeIDs = Array(newNodeIDs.subtracting(previousNodeIDs))
        let removedNodeIDs = previousNodeIDs.subtracting(newNodeIDs)

        fullLayout.addNodes(addedNodeIDs)
        fullLayout.removeNodes(removedNodeIDs)
        fullLayout.classNodeIDs = Set(enriched.nodes.filter { $0.role == .type }.map(\.id))

        // シミュレーション再開
        if viewportSize.width > 0 {
            resumeSimulation(size: viewportSize)
        }
    }

    // MARK: - Viewport / Camera

    func markUserAdjustedCamera() {
        hasUserAdjustedCamera = true
    }

    /// Viewport 変化時の初期化・再レイアウトを一元化
    func handleViewportChange(from oldSize: CGSize, to newSize: CGSize) {
        viewportSize = newSize
        guard newSize.width > 0, newSize.height > 0 else { return }

        // 初回のみシミュレーション開始（レイアウト済みなら再実行しない）
        if !hasInitialFit {
            startSimulation(size: newSize)
            return
        }

        // 実質変化がない場合は何もしない
        let dw = abs(newSize.width - oldSize.width)
        let dh = abs(newSize.height - oldSize.height)
        guard dw > 8 || dh > 8 else { return }

        // ユーザーがカメラ未操作ならサイズ変化後に再フィット
        if !hasUserAdjustedCamera {
            zoomToFit()
        }
    }

    // MARK: - シミュレーション制御

    /// alpha に応じたフレームあたり tick 数（初期は多く、収束近くは少なく）
    private func ticksPerFrame(alpha: Double) -> Int {
        if alpha > 0.5 { return 6 }
        if alpha > 0.2 { return 4 }
        if alpha > 0.05 { return 2 }
        return 1
    }

    /// 大規模グラフほど warmup を増やし、初期表示の崩れを抑える
    private func warmupIterations(for nodeCount: Int) -> Int {
        let count = max(nodeCount, 2)
        let scaled = 60 + Int(log2(Double(count)) * 22)
        return min(220, max(60, scaled))
    }

    func startSimulation(size: CGSize) {
        viewportSize = size
        hasUserAdjustedCamera = false
        let nodeIDs = document.nodes.map(\.id)
        fullLayout.classNodeIDs = Set(document.nodes.filter { $0.role == .type }.map(\.id))
        fullLayout.initialize(nodeIDs: nodeIDs, size: size)
        fullLayout.restart()

        // シミュレーション中に参照するデータをキャプチャ（毎 tick の再生成を回避）
        let simEdges = document.edges

        // 描画前にウォームアップ：大部分の収束を非表示で完了
        fullLayout.warmup(
            nodeIDs: nodeIDs,
            edges: simEdges,
            size: size,
            iterations: warmupIterations(for: nodeIDs.count)
        )
        // warmup で減衰した alpha を戻し、初回表示後も自動で十分に緩和させる
        fullLayout.reheat(alpha: 0.35)
        layoutVersion &+= 1
        hasInitialFit = true
        zoomToFit()

        // 初回表示時に focus モードが先に有効化されていた場合でも、
        // viewport が確定したこの時点で focusLayout を必ず構築する。
        if isFocusMode {
            updateFocusLayout()
            return
        }

        fullLayout.prepareForSimulation(nodeIDs: nodeIDs, edges: simEdges)

        stopSimulation()
        simulationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let batchSize = self.ticksPerFrame(alpha: self.fullLayout.alpha)
                var running = true
                for _ in 0..<batchSize {
                    running = self.fullLayout.tick(nodeIDs: nodeIDs, edges: simEdges, size: size)
                    if !running { break }
                }
                self.layoutVersion &+= 1
                if !running { return }
                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
            }
        }
    }

    /// ドラッグ後に位置を保ったまま微調整シミュレーションを再開
    func resumeSimulation(size: CGSize) {
        let layout = activeLayout
        layout.reheat()

        // タイムラインモード中は Event ノードを再 pin
        pinTimelineNodes()

        let nodeIDs: [String]
        let simEdges: [GraphEdge]
        if isFocusMode {
            nodeIDs = Array(visibleNodeIDs)
            simEdges = visibleEdges
        } else {
            nodeIDs = document.nodes.map(\.id)
            simEdges = document.edges
        }

        layout.prepareForSimulation(nodeIDs: nodeIDs, edges: simEdges)

        stopSimulation()
        simulationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let batchSize = self.ticksPerFrame(alpha: layout.alpha)
                var running = true
                for _ in 0..<batchSize {
                    running = layout.tick(nodeIDs: nodeIDs, edges: simEdges, size: size)
                    if !running { break }
                }
                self.layoutVersion &+= 1
                if !running { return }
                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
            }
        }
    }

    func stopSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
    }

    // MARK: - Zoom to Fit

    func zoomToFit(padding: CGFloat = 60) {
        let nodeIDs = visibleNodeIDs
        let nodePositions = nodeIDs.compactMap { activeLayout.positions[$0] }
        guard !nodePositions.isEmpty, viewportSize.width > 0, viewportSize.height > 0,
              let bounds = robustBounds(for: nodePositions) else { return }
        let minX = bounds.minX
        let maxX = bounds.maxX
        let minY = bounds.minY
        let maxY = bounds.maxY

        let graphWidth = maxX - minX
        let graphHeight = maxY - minY

        let availableWidth = Double(viewportSize.width) - Double(padding) * 2
        let availableHeight = Double(viewportSize.height) - Double(padding) * 2
        guard availableWidth > 1, availableHeight > 1 else { return }

        let scaleX = graphWidth > 0 ? availableWidth / graphWidth : 2.0
        let scaleY = graphHeight > 0 ? availableHeight / graphHeight : 2.0
        cameraScale = CGFloat(max(0.08, min(scaleX, scaleY, 2.0)))

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        cameraOffset = CGSize(
            width: viewportSize.width / 2 - CGFloat(centerX) * cameraScale,
            height: viewportSize.height / 2 - CGFloat(centerY) * cameraScale
        )
    }

    // MARK: - ノード種別グルーピング

    /// rdf:type を表すエッジラベルの判定
    private static let typeEdgeLabels: Set<String> = ["rdf:type", "type"]

    /// Individual ノード ID → rdf:type ターゲット ID のマッピング
    private var cachedNodeTypeMap: [String: Set<String>]?
    var nodeTypeMap: [String: Set<String>] {
        if let cached = cachedNodeTypeMap { return cached }
        var map: [String: Set<String>] = [:]
        for edge in document.edges where Self.typeEdgeLabels.contains(edge.label) {
            map[edge.sourceID, default: []].insert(edge.targetID)
        }
        cachedNodeTypeMap = map
        return map
    }

    // MARK: - プリミティブクラス階層解決

    /// subClassOf エッジラベル判定（case-insensitive、IRI末尾もサポート）
    private static func isSubClassOfLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        return lower == "subclassof"
            || lower == "rdfs:subclassof"
            || lower.hasSuffix("#subclassof")
            || lower.hasSuffix("/subclassof")
    }

    /// クラス ID → 祖先を BFS で遡り、述語にマッチする最初のクラスラベルを返す
    private func resolveAncestor(
        for classID: String,
        subClassOfMap: [String: Set<String>],
        matching predicate: (String) -> Bool
    ) -> String? {
        var visited: Set<String> = []
        var queue: [String] = [classID]
        visited.insert(classID)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let label = cachedNodeMap[current]?.label ?? localName(current)
            if predicate(label) {
                return label
            }
            guard let parents = subClassOfMap[current] else { continue }
            for parentID in parents.sorted() {
                if !visited.contains(parentID) {
                    visited.insert(parentID)
                    queue.append(parentID)
                }
            }
        }
        return nil
    }

    /// subClassOf マッピング（キャッシュ済み）
    private var cachedSubClassOfMap: [String: Set<String>]?
    private var subClassOfMap: [String: Set<String>] {
        if let cached = cachedSubClassOfMap { return cached }
        var map: [String: Set<String>] = [:]
        for edge in document.edges where Self.isSubClassOfLabel(edge.label) {
            map[edge.sourceID, default: []].insert(edge.targetID)
        }
        cachedSubClassOfMap = map
        return map
    }

    /// 指定クラスの親クラス（直接の superclass）
    func superclasses(of classID: String) -> [GraphNode] {
        guard let parentIDs = subClassOfMap[classID] else { return [] }
        return parentIDs.sorted().compactMap { cachedNodeMap[$0] }
    }

    /// インスタンスノードの rdf:type クラスノードを返す
    func typeClasses(of instanceID: String) -> [GraphNode] {
        guard let typeIDs = nodeTypeMap[instanceID] else { return [] }
        return typeIDs.sorted().compactMap { cachedNodeMap[$0] }
    }

    /// インスタンスノードの完全なクラス階層チェーンを返す
    /// rdf:type で直接のクラスを取得し、そこから superclass チェーンを辿る
    func classHierarchyChain(of instanceID: String) -> [GraphNode] {
        guard let typeIDs = nodeTypeMap[instanceID] else { return [] }
        // 最初の rdf:type クラスを使用
        guard let classID = typeIDs.sorted().first,
              let classNode = cachedNodeMap[classID] else { return [] }
        // 直接クラス + その親クラスチェーン
        var chain: [GraphNode] = [classNode]
        var currentID = classID
        while let parentIDs = subClassOfMap[currentID],
              let parentID = parentIDs.sorted().first,
              let parentNode = cachedNodeMap[parentID] {
            chain.append(parentNode)
            currentID = parentID
        }
        return chain
    }

    /// 指定クラスの子クラス（直接の subclass）
    func subclasses(of classID: String) -> [GraphNode] {
        var children: [String] = []
        for (childID, parentIDs) in subClassOfMap {
            if parentIDs.contains(classID) {
                children.append(childID)
            }
        }
        return children.sorted().compactMap { cachedNodeMap[$0] }
    }

    /// ノード ID → アイコン名（キャッシュ済み）
    /// classIcons 辞書（サブクラス含む）で BFS 解決。最も近いアイコン定義を使用。
    private var cachedNodeIconMap: [String: String]?
    var nodeIconMap: [String: String] {
        if let cached = cachedNodeIconMap { return cached }
        let scMap = subClassOfMap
        var typeMap: [String: String] = [:]

        for node in document.nodes where node.role == .type {
            if let label = resolveAncestor(for: node.id, subClassOfMap: scMap, matching: {
                GraphNodeStyle.iconName(forClassLabel: $0) != nil
            }), let icon = GraphNodeStyle.iconName(forClassLabel: label) {
                typeMap[node.id] = icon
            }
        }

        var map = typeMap
        for (nodeID, typeIDs) in nodeTypeMap {
            for typeID in typeIDs.sorted() {
                if let icon = typeMap[typeID] {
                    map[nodeID] = icon
                    break
                }
            }
        }
        cachedNodeIconMap = map
        return map
    }

    /// ノード ID → 色（キャッシュ済み）
    /// rootClassColors 辞書（22ルートクラスのみ）で BFS 解決。ドメイン色を継承。
    private var cachedNodeColorMap: [String: Color]?
    var nodeColorMap: [String: Color] {
        if let cached = cachedNodeColorMap { return cached }
        let scMap = subClassOfMap
        var typeMap: [String: Color] = [:]

        for node in document.nodes where node.role == .type {
            if let label = resolveAncestor(for: node.id, subClassOfMap: scMap, matching: {
                GraphNodeStyle.color(forClassLabel: $0) != nil
            }), let color = GraphNodeStyle.color(forClassLabel: label) {
                typeMap[node.id] = color
            }
        }

        var map = typeMap
        for (nodeID, typeIDs) in nodeTypeMap {
            for typeID in typeIDs.sorted() {
                if let color = typeMap[typeID] {
                    map[nodeID] = color
                    break
                }
            }
        }
        cachedNodeColorMap = map
        return map
    }

    /// ドキュメント内の全 Individual が持つタイプ一覧（ソート済み、フィルタ前）
    var availableIndividualTypes: [(id: String, label: String)] {
        var typeIDs: Set<String> = []
        for (_, types) in nodeTypeMap {
            typeIDs.formUnion(types)
        }
        return typeIDs
            .map { id in (id: id, label: cachedNodeMap[id]?.label ?? localName(id)) }
            .sorted { $0.label < $1.label }
    }

    // MARK: - ファセットフィルター操作

    /// プリセットフィルターを追加
    func addPreset(_ preset: GraphFilterPreset) {
        filterTokens.append(preset.token)
    }

    /// ファセットカテゴリからデフォルトトークンを追加
    func addFilterToken(for category: GraphFilterFacetCategory) {
        filterTokens.append(category.makeDefaultToken())
    }

    /// トークンを削除
    func removeFilterToken(_ token: GraphFilterToken) {
        filterTokens.removeAll { $0.id == token.id }
    }

    /// トークンを更新
    func updateFilterToken(_ token: GraphFilterToken) {
        guard let index = filterTokens.firstIndex(where: { $0.id == token.id }) else { return }
        filterTokens[index] = token
    }

    /// 全トークンをクリア
    func clearAllFilterTokens() {
        filterTokens.removeAll()
    }

    /// ドキュメント内のメトリクスキー一覧
    var availableMetricKeys: [String] {
        var keys: Set<String> = []
        for node in document.nodes {
            keys.formUnion(node.metrics.keys)
        }
        return keys.sorted()
    }

    /// 表示中ノードをロールごとにグループ化（空グループは除外）
    var visibleNodesByRole: [(role: GraphNodeRole, nodes: [GraphNode])] {
        let grouped = Dictionary(grouping: visibleNodes, by: \.role)
        let order: [GraphNodeRole] = [.type, .instance, .property, .literal]
        return order.compactMap { role in
            guard let nodes = grouped[role], !nodes.isEmpty else { return nil }
            return (role, nodes.sorted { $0.label < $1.label })
        }
    }

    // MARK: - クラス階層ツリー

    /// クラス階層のツリーノード（サイドバー表示用）
    /// クラスの子にはサブクラスとインスタンスの両方が含まれる
    struct ClassTreeNode: Identifiable, Hashable {
        let id: String
        let node: GraphNode
        var subclasses: [ClassTreeNode]?
        var instances: [GraphNode]?

        var hasChildren: Bool {
            (subclasses != nil && !(subclasses!.isEmpty))
                || (instances != nil && !(instances!.isEmpty))
        }
    }

    /// ドキュメント全体の owlClass を subClassOf 階層でツリー化
    private var cachedClassTree: [ClassTreeNode]?
    private var cachedOrphanClassNodes: [ClassTreeNode]?

    var classTree: [ClassTreeNode] {
        if let cached = cachedClassTree { return cached }
        buildAndCacheClassTree()
        return cachedClassTree ?? []
    }

    /// 階層に属さない孤立クラス（データのみで定義、オントロジーに未定義）
    var orphanClassNodes: [ClassTreeNode] {
        if let cached = cachedOrphanClassNodes { return cached }
        buildAndCacheClassTree()
        return cachedOrphanClassNodes ?? []
    }

    /// 階層クラス数（classTree に表示される数）
    var hierarchyClassCount: Int {
        var count = 0
        func countAll(_ nodes: [ClassTreeNode]) {
            for node in nodes {
                count += 1
                if let kids = node.subclasses { countAll(kids) }
            }
        }
        countAll(classTree)
        return count
    }

    /// ドキュメント内の全クラス数（type ロール + subClassOf 参加ノード）
    var totalClassCount: Int {
        var classIDs = Set(document.nodes.filter { $0.role == .type }.map(\.id))
        for (childID, parentIDs) in subClassOfMap {
            classIDs.insert(childID)
            classIDs.formUnion(parentIDs)
        }
        return classIDs.count(where: { cachedNodeMap[$0] != nil })
    }

    private func buildAndCacheClassTree() {
        var classIDs = Set(document.nodes.filter { $0.role == .type }.map(\.id))
        for (childID, parentIDs) in subClassOfMap {
            classIDs.insert(childID)
            classIDs.formUnion(parentIDs)
        }
        let classIDSet = classIDs.filter { cachedNodeMap[$0] != nil }
        guard !classIDSet.isEmpty else {
            cachedClassTree = []
            cachedOrphanClassNodes = []
            return
        }

        // subClassOf 階層に参加するクラス ID（子または親として登場）
        var hierarchyParticipants = Set<String>()
        for (childID, parentIDs) in subClassOfMap {
            if classIDSet.contains(childID) { hierarchyParticipants.insert(childID) }
            for parentID in parentIDs where classIDSet.contains(parentID) {
                hierarchyParticipants.insert(parentID)
            }
        }

        // 親 → 子クラス マッピング（subClassOfMap は 子 → 親）
        var subclassMap: [String: [String]] = [:]
        for (childID, parentIDs) in subClassOfMap {
            guard classIDSet.contains(childID) else { continue }
            for parentID in parentIDs where classIDSet.contains(parentID) {
                subclassMap[parentID, default: []].append(childID)
            }
        }

        // クラス → インスタンス マッピング（leaf type のみ）
        // 各インスタンスの rdf:type のうち、より具体的なサブクラスが同じインスタンスの
        // rdf:type に存在しない型（= leaf type）にのみ割り当てる。
        // これにより NYSE が StockExchange と FinancialMarket と Market の全てに
        // 重複表示されるのを防ぐ。

        // child が ancestor のサブクラス（推移的）か判定
        func isTransitiveSubclass(_ child: String, of ancestor: String) -> Bool {
            var visited = Set<String>()
            var queue = [child]
            while let current = queue.popLast() {
                guard visited.insert(current).inserted else { continue }
                guard let parents = subClassOfMap[current] else { continue }
                if parents.contains(ancestor) { return true }
                queue.append(contentsOf: parents)
            }
            return false
        }

        var instancesMap: [String: [GraphNode]] = [:]
        for (instanceID, typeIDs) in nodeTypeMap {
            guard let node = cachedNodeMap[instanceID], node.role == .instance else { continue }
            let validTypes = typeIDs.filter { classIDSet.contains($0) }
            // leaf type = validTypes の中に自分のサブクラスがない型
            let leafTypes = validTypes.filter { typeID in
                !validTypes.contains { otherID in
                    otherID != typeID && isTransitiveSubclass(otherID, of: typeID)
                }
            }
            for typeID in leafTypes {
                instancesMap[typeID, default: []].append(node)
            }
        }
        for (key, nodes) in instancesMap {
            instancesMap[key] = nodes.sorted { $0.label < $1.label }
        }

        // ルートクラスを特定（階層参加クラスの中で親を持たないもの）
        let nodesWithParents = Set(subClassOfMap.keys.filter { childID in
            classIDSet.contains(childID) &&
            subClassOfMap[childID]?.contains(where: { classIDSet.contains($0) }) == true
        })
        let rootIDs = hierarchyParticipants.subtracting(nodesWithParents)

        // 再帰的にツリー構築
        func buildNode(id: String, visited: inout Set<String>) -> ClassTreeNode? {
            guard let node = cachedNodeMap[id], !visited.contains(id) else { return nil }
            visited.insert(id)
            let kids = subclassMap[id]?
                .sorted { (cachedNodeMap[$0]?.label ?? $0) < (cachedNodeMap[$1]?.label ?? $1) }
                .compactMap { buildNode(id: $0, visited: &visited) }
            let instances = instancesMap[id]
            return ClassTreeNode(
                id: id,
                node: node,
                subclasses: kids?.isEmpty == true ? nil : kids,
                instances: instances?.isEmpty == true ? nil : instances
            )
        }

        var visited: Set<String> = []

        // Thing をスキップし子をルートに昇格
        var promotedRootIDs: Set<String> = []
        for id in rootIDs {
            let label = cachedNodeMap[id]?.label ?? localName(id)
            if label == "Thing" {
                visited.insert(id)
                if let kids = subclassMap[id] {
                    promotedRootIDs.formUnion(kids)
                }
            }
        }
        let effectiveRootIDs = rootIDs
            .subtracting(visited)
            .union(promotedRootIDs)

        let roots = effectiveRootIDs
            .sorted { (cachedNodeMap[$0]?.label ?? $0) < (cachedNodeMap[$1]?.label ?? $1) }
            .compactMap { buildNode(id: $0, visited: &visited) }

        // 循環参照で未訪問の階層クラスをルートに追加
        let remaining = hierarchyParticipants.subtracting(visited)
        let extras = remaining
            .sorted { (cachedNodeMap[$0]?.label ?? $0) < (cachedNodeMap[$1]?.label ?? $1) }
            .compactMap { id -> ClassTreeNode? in
                guard let node = cachedNodeMap[id] else { return nil }
                let instances = instancesMap[id]
                return ClassTreeNode(
                    id: id, node: node, subclasses: nil,
                    instances: instances?.isEmpty == true ? nil : instances
                )
            }

        cachedClassTree = roots + extras

        // 孤立クラス（階層に属さないが .type ロールのノード）
        let orphanIDs = classIDSet.subtracting(hierarchyParticipants)
        cachedOrphanClassNodes = orphanIDs
            .sorted { (cachedNodeMap[$0]?.label ?? $0) < (cachedNodeMap[$1]?.label ?? $1) }
            .compactMap { id -> ClassTreeNode? in
                guard let node = cachedNodeMap[id] else { return nil }
                let instances = instancesMap[id]
                return ClassTreeNode(
                    id: id, node: node, subclasses: nil,
                    instances: instances?.isEmpty == true ? nil : instances
                )
            }
    }

    // MARK: - インタラクション

    func selectNode(_ id: String?) {
        selectedNodeID = id
        pushHistory(id)
    }

    /// サイドバーからノードを選択し、キャンバス上で全ノードが収まるようにフィットする
    func focusOnNode(_ nodeID: String) {
        selectedNodeID = nodeID
        pushHistory(nodeID)
        zoomToFit()
    }

    func position(for nodeID: String) -> CGPoint {
        guard let pos = activeLayout.positions[nodeID] else {
            return .zero
        }
        return CGPoint(x: pos.x, y: pos.y)
    }

    func incomingEdges(for nodeID: String) -> [GraphEdge] {
        visibleEdges.filter { $0.targetID == nodeID }
    }

    func outgoingEdges(for nodeID: String) -> [GraphEdge] {
        visibleEdges.filter { $0.sourceID == nodeID }
    }

    /// Inspector 用: ラベルフィルタ適用済み・近傍フィルタなしの全エッジ
    func allIncomingEdges(for nodeID: String) -> [GraphEdge] {
        document.edges.filter { activeEdgeLabels.contains($0.label) && $0.targetID == nodeID }
    }

    func allOutgoingEdges(for nodeID: String) -> [GraphEdge] {
        document.edges.filter { activeEdgeLabels.contains($0.label) && $0.sourceID == nodeID }
    }

    // MARK: - イベント検出

    /// Date 関連のメタデータキー
    private static let dateMetadataKeys: Set<String> = [
        "occurredOnDate", "occurredAtTime", "startDate", "endDate"
    ]

    /// ノードがイベントかどうか判定
    func isEventNode(_ nodeID: String) -> Bool {
        // rdf:type でイベントクラスに属するか
        if let types = nodeTypeMap[nodeID] {
            for typeID in types {
                let name = cachedNodeMap[typeID]?.label ?? localName(typeID)
                if name.contains("Event") { return true }
            }
        }
        // メタデータに日付キーがあるか
        if let node = cachedNodeMap[nodeID] {
            if !Self.dateMetadataKeys.isDisjoint(with: node.metadata.keys) {
                return true
            }
        }
        return false
    }

    /// 選択ノードに関連するイベントノードを日付順で取得
    func relatedEvents(for nodeID: String) -> [(node: GraphNode, date: Date?, role: String)] {
        var entries: [(node: GraphNode, date: Date?, role: String)] = []
        var seen: Set<String> = []

        // Incoming: event → selectedNode (例: event hasParticipant selectedNode)
        for edge in allIncomingEdges(for: nodeID) {
            let sourceID = edge.sourceID
            guard !seen.contains(sourceID), isEventNode(sourceID),
                  let eventNode = cachedNodeMap[sourceID] else { continue }
            seen.insert(sourceID)
            entries.append((node: eventNode, date: Self.parseEventDate(from: eventNode.metadata), role: edge.label))
        }

        // Outgoing: selectedNode → event (例: selectedNode partOf event)
        for edge in allOutgoingEdges(for: nodeID) {
            let targetID = edge.targetID
            guard !seen.contains(targetID), isEventNode(targetID),
                  let eventNode = cachedNodeMap[targetID] else { continue }
            seen.insert(targetID)
            entries.append((node: eventNode, date: Self.parseEventDate(from: eventNode.metadata), role: edge.label))
        }

        // 日付あり昇順 → 日付なしラベル順
        return entries.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case (.some(let l), .some(let r)): return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.node.label < rhs.node.label
            }
        }
    }

    /// メタデータから日付を抽出（occurredOnDate > startDate > endDate の優先順）
    private static func parseEventDate(from metadata: [String: String]) -> Date? {
        for key in ["occurredOnDate", "startDate", "endDate"] {
            if let value = metadata[key], let date = parseXSDDate(value) {
                return date
            }
        }
        return nil
    }

    /// xsd 日付文字列を Date に変換（YYYY-MM-DD, YYYY-MM, YYYY）
    private static func parseXSDDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let patterns: [(format: String, regex: String)] = [
            ("yyyy-MM-dd", "^\\d{4}-\\d{2}-\\d{2}$"),
            ("yyyy-MM", "^\\d{4}-\\d{2}$"),
            ("yyyy", "^\\d{4}$"),
        ]
        for (format, pattern) in patterns {
            guard trimmed.range(of: pattern, options: .regularExpression) != nil else { continue }
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    // MARK: - プリミティブクラス分類による関連ノード検出

    /// ノードが指定ルートクラスに属するか判定
    func nodeMatchesPrimitiveClass(_ nodeID: String, className: String) -> Bool {
        let scMap = subClassOfMap
        // type ノード自身をチェック
        if cachedNodeMap[nodeID]?.role == .type {
            if let label = resolveAncestor(for: nodeID, subClassOfMap: scMap, matching: {
                GraphNodeStyle.isPrimitiveClass($0)
            }), label == className {
                return true
            }
        }
        // rdf:type で直接チェック
        if let types = nodeTypeMap[nodeID] {
            for typeID in types {
                if let label = resolveAncestor(for: typeID, subClassOfMap: scMap, matching: {
                    GraphNodeStyle.isPrimitiveClass($0)
                }), label == className {
                    return true
                }
                let name = cachedNodeMap[typeID]?.label ?? localName(typeID)
                if name.contains(className) { return true }
            }
        }
        return false
    }

    /// 選択ノードに関連する指定クラスのノードをラベル順で取得
    func relatedNodes(for nodeID: String, className: String) -> [(node: GraphNode, role: String)] {
        var entries: [(node: GraphNode, role: String)] = []
        var seen: Set<String> = []

        for edge in allIncomingEdges(for: nodeID) {
            let sourceID = edge.sourceID
            guard !seen.contains(sourceID),
                  nodeMatchesPrimitiveClass(sourceID, className: className),
                  let node = cachedNodeMap[sourceID] else { continue }
            seen.insert(sourceID)
            entries.append((node: node, role: edge.label))
        }

        for edge in allOutgoingEdges(for: nodeID) {
            let targetID = edge.targetID
            guard !seen.contains(targetID),
                  nodeMatchesPrimitiveClass(targetID, className: className),
                  let node = cachedNodeMap[targetID] else { continue }
            seen.insert(targetID)
            entries.append((node: node, role: edge.label))
        }

        return entries.sorted { $0.node.label < $1.node.label }
    }

    // MARK: - タイムラインレイアウト制御

    /// 可視 Event ノードを日付順にソートし、タイムライン上の等間隔位置を計算
    private func computeTimelinePositions() -> [String: CGPoint] {
        guard timelineOrientation != .off else { return [:] }

        // Event ノード + 日付を収集
        var eventEntries: [(id: String, date: Date)] = []
        for id in visibleNodeIDs {
            guard isEventNode(id),
                  let node = cachedNodeMap[id],
                  let date = Self.parseEventDate(from: node.metadata) else { continue }
            eventEntries.append((id: id, date: date))
        }

        guard !eventEntries.isEmpty else { return [:] }

        // 日付順ソート
        eventEntries.sort { $0.date < $1.date }

        let spacing = activeLayout.idealLength * 1.5
        let count = eventEntries.count
        let totalSpan = spacing * Double(count - 1)
        let startOffset = -totalSpan / 2

        // viewport 中心
        let cx = Double(viewportSize.width / 2 - cameraOffset.width) / Double(cameraScale)
        let cy = Double(viewportSize.height / 2 - cameraOffset.height) / Double(cameraScale)

        var positions: [String: CGPoint] = [:]
        for (i, entry) in eventEntries.enumerated() {
            let offset = startOffset + spacing * Double(i)
            switch timelineOrientation {
            case .horizontal:
                positions[entry.id] = CGPoint(x: cx + offset, y: cy)
            case .vertical:
                positions[entry.id] = CGPoint(x: cx, y: cy + offset)
            case .off:
                break
            }
        }
        return positions
    }

    /// タイムラインレイアウトを適用（ON/OFF 切り替え時に呼ばれる）
    private func applyTimelineLayout() {
        guard viewportSize.width > 0 else { return }

        if timelineOrientation == .off {
            // タイムライン解除: Event ノードの pin を外す + 軸反発を無効化
            activeLayout.timelineAxis = nil
            if let cached = cachedTimelinePositions {
                for nodeID in cached.keys {
                    activeLayout.unpin(nodeID)
                }
            }
            cachedTimelinePositions = nil
            resumeSimulation(size: viewportSize)
            return
        }

        // タイムライン位置を計算
        let targetPositions = computeTimelinePositions()
        guard !targetPositions.isEmpty else { return }
        cachedTimelinePositions = targetPositions

        // タイムライン軸反発力を設定（非Eventノードを軸から押し離す）
        let layout = activeLayout
        let cx = Double(viewportSize.width / 2 - cameraOffset.width) / Double(cameraScale)
        let cy = Double(viewportSize.height / 2 - cameraOffset.height) / Double(cameraScale)
        switch timelineOrientation {
        case .vertical:
            layout.timelineAxis = (isVertical: true, position: cx)
        case .horizontal:
            layout.timelineAxis = (isVertical: false, position: cy)
        case .off:
            break
        }

        // 現在位置をキャプチャ
        let startPositions: [String: NodePosition] = layout.positions

        // 目標: タイムライン Event ノードを目標位置、他ノードは現在位置のまま
        var targetNodePositions: [String: NodePosition] = startPositions
        for (nodeID, point) in targetPositions {
            targetNodePositions[nodeID] = NodePosition(x: Double(point.x), y: Double(point.y))
        }

        // 補間アニメーションで遷移
        animateLayoutTransition(
            from: startPositions,
            to: targetNodePositions,
            layout: layout
        )
    }

    /// タイムラインモード中に Event ノードをキャッシュ位置に pin する
    private func pinTimelineNodes() {
        guard timelineOrientation != .off, let cached = cachedTimelinePositions else { return }
        for (nodeID, point) in cached {
            activeLayout.pin(nodeID, at: point)
        }
    }

    /// ドラッグ終了時の処理（タイムラインモード対応）
    func handleDragEnd(nodeID: String, size: CGSize) {
        if timelineOrientation != .off, isEventNode(nodeID),
           let cached = cachedTimelinePositions, let point = cached[nodeID] {
            // タイムラインモード中の Event ノード: タイムライン位置に再 pin
            activeLayout.pin(nodeID, at: point)
        } else {
            activeLayout.unpin(nodeID)
        }
        resumeSimulation(size: size)
    }
}
