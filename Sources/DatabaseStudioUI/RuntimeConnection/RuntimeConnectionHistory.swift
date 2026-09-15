import Foundation
import Observation

@Observable @MainActor
final class RuntimeConnectionHistory {
    static let shared = RuntimeConnectionHistory()
    private(set) var connections: [SavedRuntimeConnection] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "RuntimeConnectionHistory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws {
        guard let data = defaults.data(forKey: key) else { connections = []; return }
        connections = try JSONDecoder().decode([SavedRuntimeConnection].self, from: data)
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    func record(endpoint: URL, databaseID: String, tenantID: String? = nil, workspaceID: String? = nil) throws -> SavedRuntimeConnection {
        try load()
        var next = connections
        let previous = next.first { $0.endpoint == endpoint && $0.databaseID == databaseID && $0.tenantID == tenantID && $0.workspaceID == workspaceID }
        let entry = SavedRuntimeConnection(id: previous?.id ?? UUID(), endpoint: endpoint,
                                          databaseID: databaseID, tenantID: tenantID, workspaceID: workspaceID, lastUsed: Date())
        next.removeAll { $0.id == entry.id }
        next.insert(entry, at: 0)
        try save(next)
        return entry
    }

    func remove(_ id: UUID) throws {
        try load()
        try save(connections.filter { $0.id != id })
    }

    private func save(_ entries: [SavedRuntimeConnection]) throws {
        let data = try JSONEncoder().encode(entries)
        defaults.set(data, forKey: key)
        connections = entries
    }
}
