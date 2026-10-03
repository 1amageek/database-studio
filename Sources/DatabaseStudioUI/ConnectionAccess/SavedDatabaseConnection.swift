import Foundation

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

    private enum CodingKeys: String, CodingKey {
        case id, name, filePath, rootDirectoryPath, isFavorite, lastUsed, useCount
        case clusterFilePath
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        // Migrate the persisted FoundationDB path field without exposing an obsolete API.
        if values.contains(.filePath) { filePath = try values.decode(String.self, forKey: .filePath) }
        else { filePath = try values.decode(String.self, forKey: .clusterFilePath) }
        rootDirectoryPath = try values.decode(String.self, forKey: .rootDirectoryPath)
        isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
        lastUsed = try values.decode(Date.self, forKey: .lastUsed)
        useCount = try values.decode(Int.self, forKey: .useCount)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(filePath, forKey: .filePath)
        try values.encode(rootDirectoryPath, forKey: .rootDirectoryPath)
        try values.encode(isFavorite, forKey: .isFavorite)
        try values.encode(lastUsed, forKey: .lastUsed)
        try values.encode(useCount, forKey: .useCount)
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
