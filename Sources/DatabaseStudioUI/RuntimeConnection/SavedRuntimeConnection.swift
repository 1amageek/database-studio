import Foundation

/// Non-secret connection history; credentials are stored separately in Keychain.
struct SavedRuntimeConnection: Codable, Identifiable, Equatable {
    let id: UUID
    let endpoint: URL
    let databaseID: String
    let tenantID: String?
    let workspaceID: String?
    var lastUsed: Date
}
