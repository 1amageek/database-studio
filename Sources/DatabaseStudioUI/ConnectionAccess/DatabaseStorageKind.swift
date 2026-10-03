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
