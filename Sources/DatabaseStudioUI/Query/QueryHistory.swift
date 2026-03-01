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

/// Query history manager.
@MainActor
public final class QueryHistoryService {
    public static let shared = QueryHistoryService()

    private let userDefaultsKey = "QueryHistory"
    private let maxHistoryCount = 20
    private var _queries: [SavedQuery] = []

    private init() {
        loadFromStorage()
    }

    public var queries: [SavedQuery] {
        _queries
    }

    public func queries(for typeName: String) -> [SavedQuery] {
        _queries.filter { $0.typeName == typeName }
    }

    public var recentQueries: [SavedQuery] {
        _queries.sorted { $0.lastUsed > $1.lastUsed }
    }

    public var frequentQueries: [SavedQuery] {
        _queries.sorted { $0.useCount > $1.useCount }
    }

    public func save(name: String, query: ItemQuery, typeName: String) {
        let savedQuery = SavedQuery(
            name: name,
            query: query,
            typeName: typeName
        )
        _queries.insert(savedQuery, at: 0)
        trimHistory()
        saveToStorage()
    }

    public func use(_ query: SavedQuery) {
        if let index = _queries.firstIndex(where: { $0.id == query.id }) {
            _queries[index].lastUsed = Date()
            _queries[index].useCount += 1
            saveToStorage()
        }
    }

    public func rename(_ query: SavedQuery, to name: String) {
        if let index = _queries.firstIndex(where: { $0.id == query.id }) {
            _queries[index].name = name
            saveToStorage()
        }
    }

    public func remove(_ query: SavedQuery) {
        _queries.removeAll { $0.id == query.id }
        saveToStorage()
    }

    public func clearAll() {
        _queries.removeAll()
        saveToStorage()
    }

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            _queries = try JSONDecoder().decode([SavedQuery].self, from: data)
        } catch {
            print("[QueryHistory] Failed to decode: \(error)")
            _queries = []
        }
    }

    private func saveToStorage() {
        do {
            let data = try JSONEncoder().encode(_queries)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            assertionFailure("[QueryHistory] Failed to encode: \(error)")
        }
    }

    private func trimHistory() {
        if _queries.count > maxHistoryCount {
            _queries = Array(_queries.prefix(maxHistoryCount))
        }
    }
}
