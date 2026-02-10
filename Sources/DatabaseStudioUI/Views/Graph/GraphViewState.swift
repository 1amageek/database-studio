import SwiftUI

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

    // MARK: - 選択

    var selectedNodeID: String? {
        didSet {
            invalidateVisibleCache()
            updateFocusLayout()
        }
    }

    var selectedNode: GraphNode? {
        guard let id = selectedNodeID else { return nil }
        return cachedNodeMap[id]
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
        // エッジラベルフィルタ適用済みのエッジを使用
        let filteredEdges = document.edges.filter { activeEdgeLabels.contains($0.label) }

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
        focusLayout.classNodeIDs = Set(document.nodes.filter { $0.kind == .owlClass }.map(\.id))
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

    /// Individuals のタイプフィルタ（nil = 全表示）
    var individualTypeFilter: String? = nil {
        didSet { invalidateVisibleCache() }
    }

    var activeEdgeLabels: Set<String> {
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

    /// タイプフィルタに一致するノード ID の集合
    private var typeFilteredNodeIDs: Set<String>? {
        guard let typeFilter = individualTypeFilter else { return nil }
        // フィルタ対象タイプに属する individual
        let matchedIndividuals = nodeTypeMap
            .filter { $0.value.contains(typeFilter) }
            .map(\.key)
        var ids = Set(matchedIndividuals)
        // タイプノード自身も含める
        ids.insert(typeFilter)
        return ids
    }

    /// フィルター適用後のエッジ（タイプフィルタ + 近傍フィルタ含む）
    var visibleEdges: [GraphEdge] {
        if let cached = cachedVisibleEdges { return cached }
        var result = document.edges.filter { activeEdgeLabels.contains($0.label) }
        // タイプフィルタ: 少なくとも片方がフィルタ対象ノードであるエッジのみ
        if let allowedIDs = typeFilteredNodeIDs {
            result = result.filter { allowedIDs.contains($0.sourceID) || allowedIDs.contains($0.targetID) }
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
        cachedVisibleNodeIDs = ids
        return ids
    }

    private func invalidateCache() {
        cachedAllEdgeLabels = nil
        cachedEdgeCounts = nil
        cachedNodeTypeMap = nil
        cachedSubClassOfMap = nil
        cachedNodePrimitiveClassMap = nil
        cachedNodeIconMap = nil
        cachedNodeColorMap = nil
        cachedNodeMap = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })
        invalidateVisibleCache()
    }

    private func invalidateVisibleCache() {
        cachedVisibleEdges = nil
        cachedVisibleNodes = nil
        cachedVisibleNodeIDs = nil
        cachedNeighborhoodNodeIDs = nil
        cachedSearchMatchedNodeIDs = nil
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

    /// クエリ実行（将来 StudioGraphService に接続）
    func executeQuery() {
        isQueryExecuting = true
        queryError = nil
        queryResults = []
        queryResultColumns = []

        Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            self.isQueryExecuting = false
            self.queryError = "SPARQL execution requires a graph service connection. Connect to a FoundationDB instance with GraphIndex to execute queries."
        }
    }

    // MARK: - シミュレーション

    private var simulationTask: Task<Void, Never>?
    private var hasInitialFit = false

    // MARK: - 初期化

    init(document: GraphDocument) {
        self.document = document
        self.activeEdgeLabels = Set(document.edges.map(\.label))
        self.cachedNodeMap = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })
    }

    // MARK: - ドキュメント更新

    func updateDocument(_ newDocument: GraphDocument) {
        let previousNodeIDs = Set(document.nodes.map(\.id))
        document = newDocument

        // 新しいエッジラベルを activeEdgeLabels に追加（既存のフィルタ状態は維持）
        let newLabels = Set(newDocument.edges.map(\.label))
        let addedLabels = newLabels.subtracting(activeEdgeLabels.union(allEdgeLabels))
        activeEdgeLabels.formUnion(addedLabels)
        // 削除されたラベルを除去
        activeEdgeLabels = activeEdgeLabels.intersection(newLabels)

        // レイアウト更新: 新規ノード追加、削除ノード除去
        let newNodeIDs = Set(newDocument.nodes.map(\.id))
        let addedNodeIDs = Array(newNodeIDs.subtracting(previousNodeIDs))
        let removedNodeIDs = previousNodeIDs.subtracting(newNodeIDs)

        fullLayout.addNodes(addedNodeIDs)
        fullLayout.removeNodes(removedNodeIDs)
        fullLayout.classNodeIDs = Set(newDocument.nodes.filter { $0.kind == .owlClass }.map(\.id))

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

        // 初回有効サイズ: シミュレーション開始
        if !hasInitialFit || oldSize.width <= 0 || oldSize.height <= 0 {
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

        // サイズ変化後の緩和
        resumeSimulation(size: newSize)
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
        fullLayout.classNodeIDs = Set(document.nodes.filter { $0.kind == .owlClass }.map(\.id))
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

        let nodeIDs: [String]
        let simEdges: [GraphEdge]
        if isFocusMode {
            nodeIDs = Array(visibleNodeIDs)
            simEdges = visibleEdges
        } else {
            nodeIDs = document.nodes.map(\.id)
            simEdges = document.edges
        }

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

    /// subClassOf エッジラベル
    private static let subClassOfLabels: Set<String> = ["subClassOf", "rdfs:subClassOf"]

    /// クラス ID → 祖先のプリミティブクラスラベルを解決（subClassOf 階層を遡る）
    /// BFS で最も近いプリミティブクラスを決定的に解決する
    private func resolvePrimitiveClass(for classID: String, subClassOfMap: [String: Set<String>]) -> String? {
        var visited: Set<String> = []
        var queue: [String] = [classID]
        visited.insert(classID)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let label = cachedNodeMap[current]?.label ?? localName(current)
            if GraphNodeStyle.isPrimitiveClass(label) {
                return label
            }
            guard let parents = subClassOfMap[current] else { continue }
            // ソートして決定的な順序にする
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
        for edge in document.edges where Self.subClassOfLabels.contains(edge.label) {
            map[edge.sourceID, default: []].insert(edge.targetID)
        }
        cachedSubClassOfMap = map
        return map
    }

    /// ノード ID → プリミティブクラスラベル（キャッシュ済み）
    private var cachedNodePrimitiveClassMap: [String: String]?
    private var nodePrimitiveClassMap: [String: String] {
        if let cached = cachedNodePrimitiveClassMap { return cached }
        let scMap = subClassOfMap
        var map: [String: String] = [:]

        // owlClass ノード → 自身またはsubClassOf 先のプリミティブクラスを解決
        for node in document.nodes where node.kind == .owlClass {
            if let primitive = resolvePrimitiveClass(for: node.id, subClassOfMap: scMap) {
                map[node.id] = primitive
            }
        }

        // Individual ノード → rdf:type のクラスが属するプリミティブクラスを解決
        // typeIDs をソートして決定的にする
        for (nodeID, typeIDs) in nodeTypeMap {
            for typeID in typeIDs.sorted() {
                if let primitive = map[typeID] {
                    map[nodeID] = primitive
                    break
                }
            }
        }

        cachedNodePrimitiveClassMap = map
        return map
    }

    /// ノード ID → プリミティブクラスに基づくアイコン名（キャッシュ済み）
    private var cachedNodeIconMap: [String: String]?
    var nodeIconMap: [String: String] {
        if let cached = cachedNodeIconMap { return cached }
        var map: [String: String] = [:]
        for (nodeID, primitive) in nodePrimitiveClassMap {
            if let icon = GraphNodeStyle.iconName(forClassLabel: primitive) {
                map[nodeID] = icon
            }
        }
        cachedNodeIconMap = map
        return map
    }

    /// ノード ID → プリミティブクラスに基づく色（キャッシュ済み）
    private var cachedNodeColorMap: [String: Color]?
    var nodeColorMap: [String: Color] {
        if let cached = cachedNodeColorMap { return cached }
        var map: [String: Color] = [:]
        for (nodeID, primitive) in nodePrimitiveClassMap {
            if let color = GraphNodeStyle.color(forClassLabel: primitive) {
                map[nodeID] = color
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

    /// 表示中ノードを種別ごとにグループ化（空グループは除外）
    var visibleNodesByKind: [(kind: GraphNodeKind, nodes: [GraphNode])] {
        let grouped = Dictionary(grouping: visibleNodes, by: \.kind)
        let order: [GraphNodeKind] = [.owlClass, .individual, .objectProperty, .dataProperty, .literal]
        return order.compactMap { kind in
            guard let nodes = grouped[kind], !nodes.isEmpty else { return nil }
            return (kind, nodes.sorted { $0.label < $1.label })
        }
    }

    // MARK: - インタラクション

    func selectNode(_ id: String?) {
        selectedNodeID = id
    }

    /// サイドバーからノードを選択し、キャンバス上で全ノードが収まるようにフィットする
    func focusOnNode(_ nodeID: String) {
        selectedNodeID = nodeID
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
}
