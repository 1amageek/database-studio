import Foundation

/// バージョンエントリー
public struct VersionEntry: Identifiable, Sendable {
    public let id: UUID
    public let version: Int
    public let timestamp: Date
    public let snapshot: [String: String]
    public let author: String?

    public init(
        id: UUID = UUID(),
        version: Int,
        timestamp: Date,
        snapshot: [String: String],
        author: String? = nil
    ) {
        self.id = id
        self.version = version
        self.timestamp = timestamp
        self.snapshot = snapshot
        self.author = author
    }
}

/// バージョン履歴ドキュメント
public struct VersionDocument: Sendable {
    public var recordID: String
    public var entityName: String
    public var versions: [VersionEntry]
    public var fieldNames: [String]

    public init(
        recordID: String = "",
        entityName: String = "",
        versions: [VersionEntry] = [],
        fieldNames: [String] = []
    ) {
        self.recordID = recordID
        self.entityName = entityName
        self.versions = versions
        self.fieldNames = fieldNames
    }

    /// 現在のアイテムデータから初期ドキュメントを構築
    public init(
        item: [String: Any],
        entityName: String
    ) {
        let id: String
        if let sid = item["id"] as? String { id = sid }
        else if let sid = item["_id"] as? String { id = sid }
        else { id = UUID().uuidString }

        self.recordID = id
        self.entityName = entityName

        var snapshot: [String: String] = [:]
        for (key, value) in item {
            snapshot[key] = String(describing: value)
        }

        self.versions = [
            VersionEntry(
                version: 1,
                timestamp: Date(),
                snapshot: snapshot
            )
        ]
        self.fieldNames = snapshot.keys.sorted()
    }
}
