import Foundation

/// Represents a discovered field from JSON data
public struct DiscoveredField: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let inferredType: FieldType
    public let sampleValues: [QueryValue]
    public let depth: Int

    public enum FieldType: String, Sendable {
        case string
        case number
        case boolean
        case array
        case vector
        case object
        case mixed
        case unknown

        public var iconName: String {
            switch self {
            case .string: return "textformat"
            case .number: return "number"
            case .boolean: return "checkmark.square"
            case .array: return "list.bullet"
            case .vector: return "arrow.up.right.and.arrow.down.left"
            case .object: return "curlybraces"
            case .mixed: return "questionmark.diamond"
            case .unknown: return "questionmark"
            }
        }
    }

    public init(
        path: String,
        name: String,
        inferredType: FieldType,
        sampleValues: [QueryValue],
        depth: Int
    ) {
        self.path = path
        self.name = name
        self.inferredType = inferredType
        self.sampleValues = sampleValues
        self.depth = depth
    }
}

/// Discovers fields from a collection of DecodedItem objects
public struct FieldDiscovery {

    /// Discover all fields from items, with sample values
    public static func discoverFields(from items: [DecodedItem], maxSamples: Int = 5) -> [DiscoveredField] {
        var fieldMap: [String: FieldInfo] = [:]

        for item in items {
            extractFields(from: item.fields, path: "", into: &fieldMap, maxSamples: maxSamples)
        }

        return fieldMap.map { path, info in
            let components = path.split(separator: ".")
            return DiscoveredField(
                path: path,
                name: String(components.last ?? ""),
                inferredType: info.type,
                sampleValues: Array(info.samples.prefix(maxSamples)),
                depth: components.count - 1
            )
        }.sorted { $0.path < $1.path }
    }

    private struct FieldInfo {
        var type: DiscoveredField.FieldType
        var samples: [QueryValue]
    }

    private static func extractFields(
        from json: [String: Any],
        path: String,
        into fieldMap: inout [String: FieldInfo],
        maxSamples: Int
    ) {
        for (key, value) in json {
            let fieldPath = path.isEmpty ? key : "\(path).\(key)"
            let type = inferType(from: value)

            if var existing = fieldMap[fieldPath] {
                if existing.type != type && type != .object && existing.type != .mixed {
                    existing.type = .mixed
                }
                if existing.samples.count < maxSamples,
                   let qv = QueryValue(from: value),
                   !existing.samples.contains(qv) {
                    existing.samples.append(qv)
                }
                fieldMap[fieldPath] = existing
            } else {
                var samples: [QueryValue] = []
                if let qv = QueryValue(from: value) {
                    samples.append(qv)
                }
                fieldMap[fieldPath] = FieldInfo(type: type, samples: samples)
            }

            if let nested = value as? [String: Any] {
                extractFields(from: nested, path: fieldPath, into: &fieldMap, maxSamples: maxSamples)
            }
        }
    }

    private static func inferType(from value: Any) -> DiscoveredField.FieldType {
        switch value {
        case is String:
            return .string
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .boolean
            }
            return .number
        case let array as [Any]:
            return inferArrayType(array)
        case is [String: Any]:
            return .object
        default:
            return .unknown
        }
    }

    private static func inferArrayType(_ array: [Any]) -> DiscoveredField.FieldType {
        let minVectorLength = 64

        guard array.count >= minVectorLength else {
            return .array
        }

        let allNumeric = array.allSatisfy { element in
            if let n = element as? NSNumber {
                return CFGetTypeID(n) != CFBooleanGetTypeID()
            }
            return false
        }

        return allNumeric ? .vector : .array
    }
}
