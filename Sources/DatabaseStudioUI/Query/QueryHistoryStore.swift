import Foundation

/// 保存されたクエリ
public struct SavedQuery: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var query: ItemQuery
    public var typeName: String
    public let createdAt: Date
    public var lastUsed: Date
    public var useCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        query: ItemQuery,
        typeName: String,
        createdAt: Date = Date(),
        lastUsed: Date = Date(),
        useCount: Int = 1
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.typeName = typeName
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.useCount = useCount
    }

    public var summary: String {
        let count = query.conditionCount
        if count == 0 {
            return "No conditions"
        } else if count == 1 {
            return "1 condition"
        } else {
            return "\(count) conditions"
        }
    }
}

/// Persists and orders saved item queries.
@MainActor
public final class QueryHistoryStore {
    public static let shared = QueryHistoryStore()

    private let queryHistoryStorageKey = "QueryHistory"
    private let maxHistoryCount = 20
    private var savedQueries: [SavedQuery] = []

    private init() {
        loadQueryHistory()
    }

    public var queries: [SavedQuery] {
        savedQueries
    }

    public func queries(for typeName: String) -> [SavedQuery] {
        savedQueries.filter { $0.typeName == typeName }
    }

    public var recentQueries: [SavedQuery] {
        savedQueries.sorted { $0.lastUsed > $1.lastUsed }
    }

    public var frequentQueries: [SavedQuery] {
        savedQueries.sorted { $0.useCount > $1.useCount }
    }

    public func save(name: String, query: ItemQuery, typeName: String) {
        let savedQuery = SavedQuery(
            name: name,
            query: query,
            typeName: typeName
        )
        savedQueries.insert(savedQuery, at: 0)
        enforceHistoryLimit()
        persistQueryHistory()
    }

    public func use(_ query: SavedQuery) {
        if let index = savedQueries.firstIndex(where: { $0.id == query.id }) {
            savedQueries[index].lastUsed = Date()
            savedQueries[index].useCount += 1
            persistQueryHistory()
        }
    }

    public func rename(_ query: SavedQuery, to name: String) {
        if let index = savedQueries.firstIndex(where: { $0.id == query.id }) {
            savedQueries[index].name = name
            persistQueryHistory()
        }
    }

    public func remove(_ query: SavedQuery) {
        savedQueries.removeAll { $0.id == query.id }
        persistQueryHistory()
    }

    public func clearAll() {
        savedQueries.removeAll()
        persistQueryHistory()
    }

    private func loadQueryHistory() {
        guard let data = UserDefaults.standard.data(forKey: queryHistoryStorageKey) else { return }
        do {
            savedQueries = try JSONDecoder().decode([SavedQuery].self, from: data)
        } catch {
            savedQueries = []
        }
    }

    private func persistQueryHistory() {
        do {
            let data = try JSONEncoder().encode(savedQueries)
            UserDefaults.standard.set(data, forKey: queryHistoryStorageKey)
        } catch {
            assertionFailure("[QueryHistory] Failed to encode: \(error)")
        }
    }

    private func enforceHistoryLimit() {
        if savedQueries.count > maxHistoryCount {
            savedQueries = Array(savedQueries.prefix(maxHistoryCount))
        }
    }
}
