import Foundation

/// Chooses the most recently successful destination across the existing histories.
enum ConnectionRestoration: Equatable {
    case local(SavedDatabaseConnection)
    case server(UUID)

    var workspaceDestination: WorkspaceDestination {
        switch self {
        case .local(let entry): .database(entry)
        case .server(let id): .server(id)
        }
    }

    static func destination(local: SavedDatabaseConnection?, server: SavedRuntimeConnection?) -> Self? {
        if let server {
            if let local {
                if server.lastUsed > local.lastUsed { return .server(server.id) }
            } else { return .server(server.id) }
        }
        return local.map(Self.local)
    }
}
