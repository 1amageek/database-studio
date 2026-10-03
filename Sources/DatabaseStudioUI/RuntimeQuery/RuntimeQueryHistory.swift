import Foundation
import Observation
import DatabaseWire

/// Persists scoped statements without credentials or query results.
@Observable @MainActor
final class RuntimeQueryHistory {
    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let scope: [String]
        let language: UInt8
        let statement: String
    }

    private(set) var entries: [Entry] = []
    @ObservationIgnored private let defaults: UserDefaults
    private let key = "RuntimeQueryHistory"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws {
        if let data = defaults.data(forKey: key) {
            let decoded = try JSONDecoder().decode([Entry].self, from: data)
            guard decoded.allSatisfy({ QueryExecuteOperation.Language(rawValue: $0.language) != nil }) else {
                throw CocoaError(.coderReadCorrupt)
            }
            entries = decoded
        } else { entries = [] }
    }

    func save(scope: [String], language: QueryExecuteOperation.Language, statement: String) throws {
        // Read before writing so a corrupt or concurrently updated history is never silently replaced.
        try load()
        var updated = entries.filter { $0.scope != scope || $0.language != language.rawValue || $0.statement != statement }
        updated.insert(.init(id: UUID(), scope: scope, language: language.rawValue, statement: statement), at: 0)
        updated = Array(updated.prefix(20))
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: key)
        entries = updated
    }
}
