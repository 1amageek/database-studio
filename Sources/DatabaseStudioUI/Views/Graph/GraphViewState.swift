import SwiftUI

/// グラフ可視化の状態管理
@Observable @MainActor
final class GraphViewState {

    // MARK: - データ

    var document: GraphDocument {
        didSet { invalidateCache() }
    }
    let layout: ForceDirectedLayout = ForceDirectedLayout()

    // MARK: - ビジュアルマッピング

    var mapping: GraphVisualMapping = GraphVisualMapping()

    // MARK: - 選択

    var selectedNodeID: String? {
        didSet { invalidateVisibleCache() }
    }

    var selectedNode: GraphNode? {
        guard let id = selectedNodeID else { return nil }
        return cachedNodeMap[id]
    }

    // MARK: - N-hop 近傍フィルタ

    /// 選択ノードから何ホップの近傍を表示するか（0 = 全ノード表示）
    var focusHops: Int = 2 {
        didSet { invalidateVisibleCache() }
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
        didSet { cachedSearchMatchedNodeIDs = nil }
    }

    private var cachedSearchMatchedNodeIDs: Set<String>?

    var searchMatchedNodeIDs: Set<String> {
        if let cached = cachedSearchMatchedNodeIDs { return cached }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            cachedSearchMatchedNodeIDs = []
            return []
        }
        let result = Set(cachedVisibleNodes.filter { $0.label.lowercased().contains(query) }.map(\.id))
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
    private var cachedVisibleNodes: [GraphNode]!
    private var cachedVisibleNodeIDs: Set<String>?
    private var cachedNodeMap: [String: GraphNode] = [:]

    /// フィルター適用後のエッジ（近傍フィルタ含む）
    var visibleEdges: [GraphEdge] {
        if let cached = cachedVisibleEdges { return cached }
        var result = document.edges.filter { activeEdgeLabels.contains($0.label) }
        // N-hop 近傍フィルタ: 選択ノードがある場合は近傍内のエッジのみ
        if let neighborhood = neighborhoodNodeIDs {
            result = result.filter { neighborhood.contains($0.sourceID) && neighborhood.contains($0.targetID) }
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
        self.cachedVisibleNodes = []
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

        layout.addNodes(addedNodeIDs)
        layout.removeNodes(removedNodeIDs)

        // シミュレーション再開
        if viewportSize.width > 0 {
            resumeSimulation(size: viewportSize)
        }
    }

    // MARK: - シミュレーション制御

    func startSimulation(size: CGSize) {
        viewportSize = size
        let nodeIDs = document.nodes.map(\.id)
        layout.initialize(nodeIDs: nodeIDs, size: size)
        layout.restart()

        // シミュレーション中に参照するデータをキャプチャ（毎 tick の再生成を回避）
        let simEdges = document.edges

        stopSimulation()
        simulationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let running = self.layout.tick(nodeIDs: nodeIDs, edges: simEdges, size: size)
                self.layoutVersion &+= 1
                if !running {
                    if !self.hasInitialFit {
                        self.hasInitialFit = true
                        self.zoomToFit()
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

    /// ドラッグ後に位置を保ったまま微調整シミュレーションを再開
    func resumeSimulation(size: CGSize) {
        layout.reheat()

        let nodeIDs = document.nodes.map(\.id)
        let simEdges = document.edges

        stopSimulation()
        simulationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let running = self.layout.tick(nodeIDs: nodeIDs, edges: simEdges, size: size)
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
        let nodePositions = nodeIDs.compactMap { layout.positions[$0] }
        guard !nodePositions.isEmpty, viewportSize.width > 0, viewportSize.height > 0 else { return }

        let minX = nodePositions.map(\.x).min()!
        let maxX = nodePositions.map(\.x).max()!
        let minY = nodePositions.map(\.y).min()!
        let maxY = nodePositions.map(\.y).max()!

        let graphWidth = maxX - minX
        let graphHeight = maxY - minY

        let availableWidth = Double(viewportSize.width) - Double(padding) * 2
        let availableHeight = Double(viewportSize.height) - Double(padding) * 2

        let scaleX = graphWidth > 0 ? availableWidth / graphWidth : 2.0
        let scaleY = graphHeight > 0 ? availableHeight / graphHeight : 2.0
        cameraScale = CGFloat(min(scaleX, scaleY, 2.0))

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        cameraOffset = CGSize(
            width: viewportSize.width / 2 - CGFloat(centerX) * cameraScale,
            height: viewportSize.height / 2 - CGFloat(centerY) * cameraScale
        )
    }

    // MARK: - ノード種別グルーピング

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

    /// サイドバーからノードを選択し、キャンバス上で中央にフォーカスする
    func focusOnNode(_ nodeID: String) {
        selectedNodeID = nodeID
        guard let pos = layout.positions[nodeID] else { return }
        cameraOffset = CGSize(
            width: viewportSize.width / 2 - CGFloat(pos.x) * cameraScale,
            height: viewportSize.height / 2 - CGFloat(pos.y) * cameraScale
        )
    }

    func position(for nodeID: String) -> CGPoint {
        guard let pos = layout.positions[nodeID] else {
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
}
