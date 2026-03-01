import Foundation

/// Backend type auto-detected from file extension.
public enum BackendType: String, Codable, Sendable {
    case foundationDB
    case sqlite

    /// Detect backend from file path extension.
    ///
    /// - `.sqlite`, `.db` → SQLite
    /// - Everything else (`.cluster`, no extension) → FoundationDB
    public static func detect(from filePath: String) -> BackendType {
        let ext = (filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "sqlite", "db":
            return .sqlite
        default:
            return .foundationDB
        }
    }
}

/// Connection information.
public struct ConnectionInfo: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var filePath: String
    public var rootDirectoryPath: String
    public var isFavorite: Bool
    public var lastUsed: Date
    public var useCount: Int

    /// Auto-detected backend type based on file extension.
    public var backendType: BackendType {
        BackendType.detect(from: filePath)
    }

    public init(
        id: UUID = UUID(),
        name: String = "",
        filePath: String,
        rootDirectoryPath: String = "",
        isFavorite: Bool = false,
        lastUsed: Date = Date(),
        useCount: Int = 1
    ) {
        self.id = id
        self.name = name.isEmpty ? Self.defaultName(from: filePath) : name
        self.filePath = filePath
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

    /// Display description for UI.
    public var displayDescription: String {
        if rootDirectoryPath.isEmpty {
            return filePath
        }
        return "\(filePath) → /\(rootDirectoryPath)"
    }

    // MARK: - Backward Compatibility

    /// Map legacy `clusterFilePath` key to `filePath` property.
    private enum CodingKeys: String, CodingKey {
        case id, name
        case filePath = "clusterFilePath"
        case rootDirectoryPath, isFavorite, lastUsed, useCount
    }
}

/// Connection history manager.
@MainActor
public final class ConnectionHistoryService {
    public static let shared = ConnectionHistoryService()

    private let userDefaultsKey = "ConnectionHistory"
    private let maxHistoryCount = 10
    private var _connections: [ConnectionInfo] = []

    private init() {
        loadFromStorage()
    }

    /// All connections.
    public var connections: [ConnectionInfo] {
        _connections
    }

    /// Most recently used connection.
    public var mostRecent: ConnectionInfo? {
        _connections.max { $0.lastUsed < $1.lastUsed }
    }

    /// Favorite connections.
    public var favorites: [ConnectionInfo] {
        _connections.filter { $0.isFavorite }
    }

    /// Recent non-favorite connections sorted by last used.
    public var recents: [ConnectionInfo] {
        _connections
            .filter { !$0.isFavorite }
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    /// Add or update a connection entry.
    public func addOrUpdate(filePath: String, rootDirectoryPath: String) {
        if let index = _connections.firstIndex(where: {
            $0.filePath == filePath && $0.rootDirectoryPath == rootDirectoryPath
        }) {
            _connections[index].lastUsed = Date()
            _connections[index].useCount += 1
        } else {
            let connection = ConnectionInfo(
                filePath: filePath,
                rootDirectoryPath: rootDirectoryPath
            )
            _connections.insert(connection, at: 0)
            trimHistory()
        }
        saveToStorage()
    }

    /// Toggle favorite status.
    public func toggleFavorite(_ connection: ConnectionInfo) {
        if let index = _connections.firstIndex(where: { $0.id == connection.id }) {
            _connections[index].isFavorite.toggle()
            saveToStorage()
        }
    }

    /// Rename a connection.
    public func rename(_ connection: ConnectionInfo, to name: String) {
        if let index = _connections.firstIndex(where: { $0.id == connection.id }) {
            _connections[index].name = name
            saveToStorage()
        }
    }

    /// Remove a connection.
    public func remove(_ connection: ConnectionInfo) {
        _connections.removeAll { $0.id == connection.id }
        saveToStorage()
    }

    /// Clear history (keeps favorites).
    public func clearHistory() {
        _connections.removeAll { !$0.isFavorite }
        saveToStorage()
    }

    // MARK: - Persistence

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            _connections = try JSONDecoder().decode([ConnectionInfo].self, from: data)
        } catch {
            print("[ConnectionHistory] Failed to decode: \(error)")
            _connections = []
        }
    }

    private func saveToStorage() {
        do {
            let data = try JSONEncoder().encode(_connections)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            assertionFailure("[ConnectionHistory] Failed to encode: \(error)")
        }
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
