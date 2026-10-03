import Foundation
import Observation

/// Persists and orders previously used database connections.
@Observable @MainActor
public final class ConnectionHistoryStore {
    public static let shared = ConnectionHistoryStore()

    @ObservationIgnored private let defaults: UserDefaults
    public private(set) var failure: String?

    @ObservationIgnored private let connectionHistoryStorageKey = "ConnectionHistory"
    @ObservationIgnored private let maxHistoryCount = 10
    private var historyEntries: [SavedDatabaseConnection] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do { try load() }
        catch { failure = error.localizedDescription }
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

    /// Adds a successful connection while retaining its saved identity and preferences.
    public func addOrUpdate(filePath: String, rootDirectoryPath: String) throws {
        try load()
        let path = Self.normalizedPath(filePath)
        if let index = historyEntries.firstIndex(where: {
            Self.normalizedPath($0.filePath) == path && $0.rootDirectoryPath == rootDirectoryPath
        }) {
            historyEntries[index].filePath = path
            historyEntries[index].lastUsed = Date()
            historyEntries[index].useCount += 1
        } else {
            historyEntries.insert(SavedDatabaseConnection(filePath: path, rootDirectoryPath: rootDirectoryPath), at: 0)
            enforceHistoryLimit()
        }
        try persist()
    }

    public func toggleFavorite(_ connection: SavedDatabaseConnection) throws {
        try load()
        if let index = historyEntries.firstIndex(where: { $0.id == connection.id }) {
            historyEntries[index].isFavorite.toggle()
            try persist()
        }
    }

    public func rename(_ connection: SavedDatabaseConnection, to name: String) throws {
        try load()
        if let index = historyEntries.firstIndex(where: { $0.id == connection.id }) {
            historyEntries[index].name = name
            try persist()
        }
    }

    public func remove(_ connection: SavedDatabaseConnection) throws {
        try load()
        historyEntries.removeAll { $0.id == connection.id }
        try persist()
    }

    /// Clears non-favorite entries, preserving favorite destinations.
    public func clearHistory() throws {
        try load()
        historyEntries.removeAll { !$0.isFavorite }
        try persist()
    }

    public func load() throws {
        do {
            let entries: [SavedDatabaseConnection]
            if let data = defaults.data(forKey: connectionHistoryStorageKey) {
                entries = try JSONDecoder().decode([SavedDatabaseConnection].self, from: data)
            } else { entries = [] }
            historyEntries = entries
            failure = nil
        } catch {
            failure = error.localizedDescription
            throw error
        }
    }

    private func persist() throws {
        do {
            let data = try JSONEncoder().encode(historyEntries)
            defaults.set(data, forKey: connectionHistoryStorageKey)
            failure = nil
        } catch {
            failure = error.localizedDescription
            throw error
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
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
