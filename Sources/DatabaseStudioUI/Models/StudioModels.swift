import Foundation
import DatabaseKit

/// A database record prepared for presentation in Database Studio.
public struct StudioRecord: Identifiable {
    public let id: String
    public let typeName: String
    public let fields: [String: Any]
    public let jsonByteCount: Int

    public init(id: String, typeName: String, fields: [String: Any], jsonByteCount: Int) {
        self.id = id
        self.typeName = typeName
        self.fields = fields
        self.jsonByteCount = jsonByteCount
    }

    /// A formatted JSON representation of the record fields.
    public func formattedJSON() throws -> String {
        // JSONSerialization raises an ObjC exception (not a Swift error) for
        // unsupported values, so validity must be checked before encoding.
        guard JSONSerialization.isValidJSONObject(fields) else {
            throw StudioRecordFormattingError.jsonEncodingFailed(
                id,
                "record contains values that are not representable in JSON"
            )
        }
        do {
            let encodedFields = try JSONSerialization.data(
                withJSONObject: fields,
                options: [.prettyPrinted, .sortedKeys]
            )
            guard let formattedFields = String(data: encodedFields, encoding: .utf8) else {
                throw StudioRecordFormattingError.invalidUTF8(id)
            }
            return formattedFields
        } catch let formattingError as StudioRecordFormattingError {
            throw formattingError
        } catch {
            throw StudioRecordFormattingError.jsonEncodingFailed(id, error.localizedDescription)
        }
    }

    /// The formatted size of the JSON representation.
    public var formattedJSONSize: String {
        HexFormatter.formatByteCount(jsonByteCount)
    }

    /// Returns display text for the JSON value at the specified field path.
    public func jsonValue(at path: String) -> String {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = fields

        for component in components {
            if let object = current as? [String: Any], let value = object[component] {
                current = value
            } else {
                return "-"
            }
        }

        return formatValue(current)
    }

    private func formatValue(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return "\(number)"
        }
        if let array = value as? [Any] {
            if array.count > 64 {
                return "[vector: \(array.count)d]"
            }
            return "[\(array.count) items]"
        }
        if let object = value as? [String: Any] {
            return "{\(object.count) fields}"
        }
        return String(describing: value)
    }
}

/// A record presentation failure that must be shown instead of substituted data.
public enum StudioRecordFormattingError: LocalizedError, Sendable {
    case jsonEncodingFailed(String, String)
    case invalidUTF8(String)
    case pasteboardWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .jsonEncodingFailed(let identifier, let message):
            return "Could not encode record \(identifier) as JSON: \(message)"
        case .invalidUTF8(let identifier):
            return "The JSON representation of record \(identifier) is not valid UTF-8"
        case .pasteboardWriteFailed(let identifier):
            return "Could not copy record \(identifier) to the pasteboard"
        }
    }
}

/// A schema entity group presented in the database navigation tree.
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

/// The current database navigation selection.
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

/// Aggregate storage statistics for a record collection.
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

/// Aggregate storage statistics for an index.
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

/// A page of database records and its continuation state.
public struct StudioRecordPage {
    public let items: [StudioRecord]
    public let hasMore: Bool
    public let offset: Int
    public let limit: Int

    public var nextOffset: Int {
        offset + items.count
    }

    public init(items: [StudioRecord], hasMore: Bool, offset: Int, limit: Int) {
        self.items = items
        self.hasMore = hasMore
        self.offset = offset
        self.limit = limit
    }
}
