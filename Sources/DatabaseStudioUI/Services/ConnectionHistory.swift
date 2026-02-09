import Foundation

/// 接続情報
public struct ConnectionInfo: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var clusterFilePath: String
    public var rootDirectoryPath: String
    public var isFavorite: Bool
    public var lastUsed: Date
    public var useCount: Int

    public init(
        id: UUID = UUID(),
        name: String = "",
        clusterFilePath: String,
        rootDirectoryPath: String = "",
        isFavorite: Bool = false,
        lastUsed: Date = Date(),
        useCount: Int = 1
    ) {
        self.id = id
        self.name = name.isEmpty ? Self.defaultName(from: clusterFilePath) : name
        self.clusterFilePath = clusterFilePath
        self.rootDirectoryPath = rootDirectoryPath
        self.isFavorite = isFavorite
        self.lastUsed = lastUsed
        self.useCount = useCount
    }

    private static func defaultName(from path: String) -> String {
        let fileName = (path as NSString).lastPathComponent
        let name = (fileName as NSString).deletingPathExtension
        return name.isEmpty ? "Connection" : name
    }

    /// 表示用の簡易説明
    public var displayDescription: String {
        if rootDirectoryPath.isEmpty {
            return clusterFilePath
        }
        return "\(clusterFilePath) → /\(rootDirectoryPath)"
    }
}

/// 接続履歴管理
public final class ConnectionHistoryService: @unchecked Sendable {
    public static let shared = ConnectionHistoryService()

    private let userDefaultsKey = "ConnectionHistory"
    private let maxHistoryCount = 10
    private var _connections: [ConnectionInfo] = []

    private init() {
        loadFromStorage()
    }

    /// 全接続履歴
    public var connections: [ConnectionInfo] {
        _connections
    }

    /// 最後に使用した接続
    public var mostRecent: ConnectionInfo? {
        _connections.max { $0.lastUsed < $1.lastUsed }
    }

    /// お気に入り接続
    public var favorites: [ConnectionInfo] {
        _connections.filter { $0.isFavorite }
    }

    /// 最近使用した接続（お気に入り以外）
    public var recents: [ConnectionInfo] {
        _connections
            .filter { !$0.isFavorite }
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    /// 接続を追加または更新
    public func addOrUpdate(clusterFilePath: String, rootDirectoryPath: String) {
        if let index = _connections.firstIndex(where: {
            $0.clusterFilePath == clusterFilePath && $0.rootDirectoryPath == rootDirectoryPath
        }) {
            _connections[index].lastUsed = Date()
            _connections[index].useCount += 1
        } else {
            let connection = ConnectionInfo(
                clusterFilePath: clusterFilePath,
                rootDirectoryPath: rootDirectoryPath
            )
            _connections.insert(connection, at: 0)
            trimHistory()
        }
        saveToStorage()
    }

    /// お気に入りをトグル
    public func toggleFavorite(_ connection: ConnectionInfo) {
        if let index = _connections.firstIndex(where: { $0.id == connection.id }) {
            _connections[index].isFavorite.toggle()
            saveToStorage()
        }
    }

    /// 接続名を更新
    public func rename(_ connection: ConnectionInfo, to name: String) {
        if let index = _connections.firstIndex(where: { $0.id == connection.id }) {
            _connections[index].name = name
            saveToStorage()
        }
    }

    /// 接続を削除
    public func remove(_ connection: ConnectionInfo) {
        _connections.removeAll { $0.id == connection.id }
        saveToStorage()
    }

    /// 履歴をクリア（お気に入りは残す）
    public func clearHistory() {
        _connections.removeAll { !$0.isFavorite }
        saveToStorage()
    }

    // MARK: - Persistence

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let connections = try? JSONDecoder().decode([ConnectionInfo].self, from: data) else {
            return
        }
        _connections = connections
    }

    private func saveToStorage() {
        guard let data = try? JSONEncoder().encode(_connections) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func trimHistory() {
        let nonFavorites = _connections.filter { !$0.isFavorite }
        if nonFavorites.count > maxHistoryCount {
            let sorted = nonFavorites.sorted { $0.lastUsed > $1.lastUsed }
            let toRemove = Set(sorted.dropFirst(maxHistoryCount).map { $0.id })
            _connections.removeAll { toRemove.contains($0.id) }
        }
    }
}
