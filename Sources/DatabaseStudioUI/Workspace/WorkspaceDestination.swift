import Foundation

/// Non-secret connection selection restored by the base workspace scene.
public enum WorkspaceDestination: Codable, Hashable, Sendable {
    case database(SavedDatabaseConnection?)
    case server(UUID?)
}
