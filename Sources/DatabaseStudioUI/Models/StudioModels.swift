import Foundation
import Core

/// デコードされたアイテム
public struct DecodedItem: Identifiable {
    public let id: String
    public let typeName: String
    public let fields: [String: Any]
    public let rawSize: Int

    public init(id: String, typeName: String, fields: [String: Any], rawSize: Int) {
        self.id = id
        self.typeName = typeName
        self.fields = fields
        self.rawSize = rawSize
    }

    /// JSON としてのプレティプリント
    public var prettyJSON: String {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    /// フォーマットされたサイズ
    public var formattedSize: String {
        HexFormatter.formatByteCount(rawSize)
    }

    /// 指定パスの JSON 値を文字列で取得
    public func jsonValue(at path: String) -> String {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = fields

        for component in components {
            if let dict = current as? [String: Any], let val = dict[component] {
                current = val
            } else {
                return "-"
            }
        }

        return formatValue(current)
    }

    private func formatValue(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let str = value as? String { return str }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue ? "true" : "false"
            }
            return "\(num)"
        }
        if let array = value as? [Any] {
            if array.count > 64 {
                return "[vector: \(array.count)d]"
            }
            return "[\(array.count) items]"
        }
        if let dict = value as? [String: Any] {
            return "{\(dict.count) fields}"
        }
        return String(describing: value)
    }
}

/// エンティティツリーノード（サイドバー用）
public struct EntityTreeNode: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let path: [String]
    public var children: [EntityTreeNode]
    public var entities: [Schema.Entity]

    public init(name: String, path: [String], children: [EntityTreeNode] = [], entities: [Schema.Entity] = []) {
        self.id = path.joined(separator: "/")
        self.name = name
        self.path = path
        self.children = children
        self.entities = entities
    }
}

/// ツリー選択状態
public enum StudioSelection: Hashable {
    case entity(String)  // entity name
    case index(String, String)  // entity name, index name

    public var entityName: String? {
        switch self {
        case .entity(let name): return name
        case .index(let name, _): return name
        }
    }

    public var indexName: String? {
        if case .index(_, let name) = self {
            return name
        }
        return nil
    }
}

/// コレクション統計
public struct CollectionStats: Sendable {
    public let typeName: String
    public let documentCount: Int
    public let storageSize: Int

    public var avgDocumentSize: Int {
        guard documentCount > 0 else { return 0 }
        return storageSize / documentCount
    }

    public init(typeName: String, documentCount: Int, storageSize: Int) {
        self.typeName = typeName
        self.documentCount = documentCount
        self.storageSize = storageSize
    }
}

/// インデックス統計
public struct IndexStats: Sendable {
    public let indexName: String
    public let kindIdentifier: String
    public let entryCount: Int
    public let storageSize: Int

    public init(indexName: String, kindIdentifier: String, entryCount: Int, storageSize: Int) {
        self.indexName = indexName
        self.kindIdentifier = kindIdentifier
        self.entryCount = entryCount
        self.storageSize = storageSize
    }
}

/// アイテムページ（ページネーション）
public struct DecodedItemPage {
    public let items: [DecodedItem]
    public let hasMore: Bool
    public let offset: Int
    public let limit: Int

    public var nextOffset: Int {
        offset + items.count
    }

    public init(items: [DecodedItem], hasMore: Bool, offset: Int, limit: Int) {
        self.items = items
        self.hasMore = hasMore
        self.offset = offset
        self.limit = limit
    }
}
