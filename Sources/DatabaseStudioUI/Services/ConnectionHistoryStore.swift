import Foundation

/// The database storage implementation selected by a connection path.
public enum DatabaseStorageKind: String, Codable, Sendable {
    case foundationDB
    case sqlite

    /// Detects the storage kind from a database file path.
    ///
    /// - `.sqlite`, `.db` → SQLite
    /// - Everything else (`.cluster`, no extension) → FoundationDB
    public static func detect(from filePath: String) -> DatabaseStorageKind {
        let fileExtension = (filePath as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "sqlite", "db":
            return .sqlite
        default:
            return .foundationDB
        }
    }
}

/// A database connection saved in the user's connection history.
public struct SavedDatabaseConnection: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var filePath: String
    public var rootDirectoryPath: String
    public var isFavorite: Bool
    public var lastUsed: Date
    public var useCount: Int

    /// The storage kind selected by the connection path.
    public var storageKind: DatabaseStorageKind {
        DatabaseStorageKind.detect(from: filePath)
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
        self.name = name.isEmpty ? Self.inferredName(from: filePath) : name
        self.filePath = filePath
        self.rootDirectoryPath = rootDirectoryPath
        self.isFavorite = isFavorite
        self.lastUsed = lastUsed
        self.useCount = useCount
    }

    private static func inferredName(from filePath: String) -> String {
        let fileName = (filePath as NSString).lastPathComponent
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

}

/// Persists and orders previously used database connections.
@MainActor
public final class ConnectionHistoryStore {
    public static let shared = ConnectionHistoryStore()

    private let connectionHistoryStorageKey = "ConnectionHistory"
    private let maxHistoryCount = 10
    private var historyEntries: [SavedDatabaseConnection] = []

    private init() {
        loadConnectionHistory()
    }

    /// All connections.
    public var connections: [SavedDatabaseConnection] {
        historyEntries
    }

    /// Most recently used connection.
    public var mostRecent: SavedDatabaseConnection? {
        historyEntries.max { $0.lastUsed < $1.lastUsed }
    }

    /// Favorite connections.
    public var favorites: [SavedDatabaseConnection] {
        historyEntries.filter { $0.isFavorite }
    }

    /// Recent non-favorite connections sorted by last used.
    public var recents: [SavedDatabaseConnection] {
        historyEntries
            .filter { !$0.isFavorite }
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    /// Add or update a connection entry.
    public func addOrUpdate(filePath: String, rootDirectoryPath: String) {
        if let index = historyEntries.firstIndex(where: {
            $0.filePath == filePath && $0.rootDirectoryPath == rootDirectoryPath
        }) {
            historyEntries[index].lastUsed = Date()
            historyEntries[index].useCount += 1
        } else {
            let connection = SavedDatabaseConnection(
                filePath: filePath,
                rootDirectoryPath: rootDirectoryPath
            )
            historyEntries.insert(connection, at: 0)
            enforceHistoryLimit()
        }
        persistConnectionHistory()
    }

    /// Toggle favorite status.
    public func toggleFavorite(_ connection: SavedDatabaseConnection) {
        if let index = historyEntries.firstIndex(where: { $0.id == connection.id }) {
            historyEntries[index].isFavorite.toggle()
            persistConnectionHistory()
        }
    }

    /// Rename a connection.
    public func rename(_ connection: SavedDatabaseConnection, to name: String) {
        if let index = historyEntries.firstIndex(where: { $0.id == connection.id }) {
            historyEntries[index].name = name
            persistConnectionHistory()
        }
    }

    /// Remove a connection.
    public func remove(_ connection: SavedDatabaseConnection) {
        historyEntries.removeAll { $0.id == connection.id }
        persistConnectionHistory()
    }

    /// Clear history (keeps favorites).
    public func clearHistory() {
        historyEntries.removeAll { !$0.isFavorite }
        persistConnectionHistory()
    }

    // MARK: - Persistence

    private func loadConnectionHistory() {
        guard let data = UserDefaults.standard.data(forKey: connectionHistoryStorageKey) else { return }
        do {
            historyEntries = try JSONDecoder().decode([SavedDatabaseConnection].self, from: data)
        } catch {
            historyEntries = []
        }
    }

    private func persistConnectionHistory() {
        do {
            let data = try JSONEncoder().encode(historyEntries)
            UserDefaults.standard.set(data, forKey: connectionHistoryStorageKey)
        } catch {
            assertionFailure("[ConnectionHistory] Failed to encode: \(error)")
        }
    }

    private func enforceHistoryLimit() {
        let nonFavoriteConnections = historyEntries.filter { !$0.isFavorite }
        if nonFavoriteConnections.count > maxHistoryCount {
            let recentConnections = nonFavoriteConnections.sorted { $0.lastUsed > $1.lastUsed }
            let expiredIdentifiers = Set(recentConnections.dropFirst(maxHistoryCount).map { $0.id })
            historyEntries.removeAll { expiredIdentifiers.contains($0.id) }
        }
    }
}
