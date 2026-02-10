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
    var focusHops: Int = 1 {
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
        let result = Set(visibleNodes.filter { node in
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
        cachedNodeIconMap = nil
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

        layout.addNodes(addedNodeIDs)
        layout.removeNodes(removedNodeIDs)
        layout.classNodeIDs = Set(newDocument.nodes.filter { $0.kind == .owlClass }.map(\.id))

        // シミュレーション再開
        if viewportSize.width > 0 {
            resumeSimulation(size: viewportSize)
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

    func startSimulation(size: CGSize) {
        viewportSize = size
        let nodeIDs = document.nodes.map(\.id)
        layout.classNodeIDs = Set(document.nodes.filter { $0.kind == .owlClass }.map(\.id))
        layout.initialize(nodeIDs: nodeIDs, size: size)
        layout.restart()

        // シミュレーション中に参照するデータをキャプチャ（毎 tick の再生成を回避）
        let simEdges = document.edges

        // 描画前にウォームアップ：大部分の収束を非表示で完了
        layout.warmup(nodeIDs: nodeIDs, edges: simEdges, size: size)
        layoutVersion &+= 1

        stopSimulation()
        simulationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let batchSize = self.ticksPerFrame(alpha: self.layout.alpha)
                var running = true
                for _ in 0..<batchSize {
                    running = self.layout.tick(nodeIDs: nodeIDs, edges: simEdges, size: size)
                    if !running { break }
                }
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
                let batchSize = self.ticksPerFrame(alpha: self.layout.alpha)
                var running = true
                for _ in 0..<batchSize {
                    running = self.layout.tick(nodeIDs: nodeIDs, edges: simEdges, size: size)
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

    /// ノード ID → プリミティブクラスに基づくアイコン名（キャッシュ済み）
    private var cachedNodeIconMap: [String: String]?
    var nodeIconMap: [String: String] {
        if let cached = cachedNodeIconMap { return cached }
        var map: [String: String] = [:]
        for (nodeID, typeIDs) in nodeTypeMap {
            for typeID in typeIDs {
                let classLabel = cachedNodeMap[typeID]?.label ?? localName(typeID)
                if let icon = GraphNodeStyle.iconName(forClassLabel: classLabel) {
                    map[nodeID] = icon
                    break
                }
            }
        }
        // owlClass 自身にもアイコンを設定
        for node in document.nodes where node.kind == .owlClass {
            if let icon = GraphNodeStyle.iconName(forClassLabel: node.label) {
                map[node.id] = icon
            }
        }
        cachedNodeIconMap = map
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
