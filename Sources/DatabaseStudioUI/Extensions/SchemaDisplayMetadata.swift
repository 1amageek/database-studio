import Foundation
import DatabaseKit

// MARK: - Index Kind Presentation

extension IndexKindMetadata {
    /// The localized-neutral label shown for the index kind.
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

    /// The SF Symbol representing the index kind.
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

// MARK: - Field Type Presentation

extension FieldSchemaType {
    /// The label shown for the field type.
    public var displayName: String {
        switch self {
        case .string: return "String"
        case .int8: return "Int8"
        case .int16: return "Int16"
        case .int32: return "Int32"
        case .int64: return "Int64"
        case .uint8: return "UInt8"
        case .uint16: return "UInt16"
        case .uint32: return "UInt32"
        case .uint64: return "UInt64"
        case .float32: return "Float32"
        case .float64: return "Float64"
        case .decimal: return "Decimal"
        case .bool: return "Bool"
        case .bytes: return "Bytes"
        case .date: return "Date"
        case .time: return "Time"
        case .dateTime: return "DateTime"
        case .timestamp: return "Timestamp"
        case .timeSpan: return "TimeSpan"
        case .calendarPeriod: return "CalendarPeriod"
        case .geographicPoint: return "GeoPoint"
        case .geographicPosition: return "GeoPosition"
        case .vector: return "Vector"
        case .uuid: return "UUID"
        case .object: return "Object"
        case .nested: return "Nested"
        case .enum: return "Enum"
        case .rdfTerm: return "RDF Term"
        case .reference: return "Reference"
        }
    }

    /// The SF Symbol representing the field type.
    public var iconName: String {
        switch self {
        case .string, .uuid: return "textformat"
        case .int8, .int16, .int32, .int64,
             .uint8, .uint16, .uint32, .uint64: return "number"
        case .float32, .float64, .decimal: return "function"
        case .bool: return "checkmark.circle"
        case .bytes: return "doc.fill"
        case .date, .time, .dateTime, .timestamp,
             .timeSpan, .calendarPeriod: return "calendar"
        case .geographicPoint, .geographicPosition: return "mappin.and.ellipse"
        case .vector: return "chart.dots.scatter"
        case .object, .nested: return "rectangle.3.group"
        case .enum: return "list.dash"
        case .rdfTerm: return "point.3.connected.trianglepath.dotted"
        case .reference: return "link"
        }
    }
}

// MARK: - Entity Schema Presentation

extension Schema.Entity {
    /// A display-ready representation of the entity directory path.
    public var directoryPathDisplay: String {
        directoryComponents.map { component in
            switch component {
            case .staticPath(let path): return path
            case .dynamicField(let fieldName): return "<\(fieldName)>"
            }
        }.joined(separator: " / ")
    }

    /// Field names that provide dynamic directory components.
    public var dynamicFieldNames: [String] {
        directoryComponents.compactMap { component in
            if case .dynamicField(let name) = component {
                return name
            }
            return nil
        }
    }

    /// Whether the entity uses at least one dynamic partition component.
    public var hasDynamicPartition: Bool {
        !dynamicFieldNames.isEmpty
    }
}
