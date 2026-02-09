import Foundation
import Core

// MARK: - AnyIndexKind Display

extension AnyIndexKind {
    /// 表示名
    public var displayName: String {
        switch identifier {
        case "scalar": return "Scalar"
        case "vector": return "Vector"
        case "fulltext": return "Full Text"
        case "spatial": return "Spatial"
        case "graph": return "Graph"
        case "rank": return "Rank"
        case "bitmap": return "Bitmap"
        case "version": return "Version"
        case "relationship": return "Relationship"
        case "leaderboard": return "Leaderboard"
        case "permuted": return "Permuted"
        case "count": return "Count"
        case "sum": return "Sum"
        case "average": return "Average"
        case "min": return "Min"
        case "max": return "Max"
        default: return identifier.capitalized
        }
    }

    /// SF Symbol 名
    public var symbolName: String {
        switch identifier {
        case "scalar": return "line.3.horizontal.decrease"
        case "vector": return "arrow.up.right"
        case "fulltext": return "text.magnifyingglass"
        case "spatial": return "map"
        case "graph": return "point.3.connected.trianglepath.dotted"
        case "rank": return "chart.bar"
        case "bitmap": return "square.grid.3x3"
        case "version": return "clock.arrow.circlepath"
        case "relationship": return "arrow.left.arrow.right"
        case "leaderboard": return "trophy"
        case "permuted": return "arrow.triangle.swap"
        case "count": return "number"
        case "sum": return "sum"
        case "average": return "divide"
        case "min": return "arrow.down.to.line"
        case "max": return "arrow.up.to.line"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - FieldSchemaType Display

extension FieldSchemaType {
    /// 表示名
    public var displayName: String {
        switch self {
        case .string: return "String"
        case .int: return "Int"
        case .int8: return "Int8"
        case .int16: return "Int16"
        case .int32: return "Int32"
        case .int64: return "Int64"
        case .uint: return "UInt"
        case .uint8: return "UInt8"
        case .uint16: return "UInt16"
        case .uint32: return "UInt32"
        case .uint64: return "UInt64"
        case .float: return "Float"
        case .double: return "Double"
        case .bool: return "Bool"
        case .data: return "Data"
        case .date: return "Date"
        case .uuid: return "UUID"
        case .nested: return "Nested"
        case .enum: return "Enum"
        }
    }

    /// SF Symbol 名
    public var iconName: String {
        switch self {
        case .string, .uuid: return "textformat"
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64: return "number"
        case .float, .double: return "function"
        case .bool: return "checkmark.circle"
        case .data: return "doc.fill"
        case .date: return "calendar"
        case .nested: return "rectangle.3.group"
        case .enum: return "list.dash"
        }
    }
}

// MARK: - Schema.Entity Display

extension Schema.Entity {
    /// ディレクトリパスの表示文字列
    public var directoryPathDisplay: String {
        directoryComponents.map { component in
            switch component {
            case .staticPath(let path): return path
            case .dynamicField(let fieldName): return "<\(fieldName)>"
            }
        }.joined(separator: " / ")
    }

    /// 動的ディレクトリフィールド名の一覧
    public var dynamicFieldNames: [String] {
        directoryComponents.compactMap { component in
            if case .dynamicField(let name) = component {
                return name
            }
            return nil
        }
    }

    /// 動的パーティションを持つかどうか
    public var hasDynamicPartition: Bool {
        !dynamicFieldNames.isEmpty
    }
}
