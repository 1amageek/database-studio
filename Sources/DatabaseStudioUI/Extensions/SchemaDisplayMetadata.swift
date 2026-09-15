import DatabaseKit

// MARK: - Index presentation

extension IndexType {
    /// The localized-neutral label shown for the semantic index family.
    public var displayName: String {
        switch self {
        case .ordered: "Ordered"
        case .aggregate(let function): function.displayName
        case .updateCount: "Update Count"
        case .history: "History"
        case .bitmap: "Bitmap"
        case .leaderboard: "Leaderboard"
        case .vector: "Vector"
        case .text(.fullText): "Full Text"
        case .text(.autocomplete): "Autocomplete"
        case .spatial: "Spatial"
        case .rank: "Rank"
        case .graph(.property): "Property Graph"
        case .graph(.rdf): "RDF Dataset"
        case .graph(.ontologyProjection): "Ontology Projection"
        case .custom(let identifier): identifier
        }
    }

    /// The SF Symbol representing the semantic index family.
    public var symbolName: String {
        switch self {
        case .ordered: "line.3.horizontal.decrease"
        case .aggregate(.count), .updateCount: "number"
        case .aggregate(.sum): "sum"
        case .aggregate(.average): "divide"
        case .aggregate(.minimum): "arrow.down.to.line"
        case .aggregate(.maximum): "arrow.up.to.line"
        case .aggregate(.nonNullCount), .aggregate(.approximateDistinct):
            "number.square"
        case .aggregate(.percentile): "chart.line.uptrend.xyaxis"
        case .history: "clock.arrow.circlepath"
        case .bitmap: "square.grid.3x3"
        case .leaderboard: "trophy"
        case .vector: "arrow.up.right"
        case .text: "text.magnifyingglass"
        case .spatial: "map"
        case .rank: "chart.bar"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .custom: "puzzlepiece.extension"
        }
    }
}

private extension AggregateFunctionType {
    var displayName: String {
        switch self {
        case .count: "Count"
        case .sum: "Sum"
        case .minimum: "Minimum"
        case .maximum: "Maximum"
        case .average: "Average"
        case .nonNullCount: "Non-null Count"
        case .approximateDistinct: "Approximate Distinct"
        case .percentile: "Percentile"
        }
    }
}

extension IndexDescriptor {
    /// Complete logical configuration rendered without inferring a physical
    /// storage layout from schema semantics.
    var configurationDisplay: [String: String] {
        switch declaration.definition {
        case .ordered:
            return [:]
        case .aggregate(let function, _, _):
            switch function {
            case .approximateDistinct(let precision):
                return ["Precision": String(precision)]
            case .percentile(let compression):
                return ["Compression": String(compression)]
            default:
                return [:]
            }
        case .updateCount, .bitmap, .rank:
            return [:]
        case .history(_, let retention):
            return ["Retention": retention.displayText]
        case .leaderboard(_, _, let window, let count):
            return [
                "Window": window.displayText,
                "Window Count": String(count),
            ]
        case .vector(_, let dimensions, let metric):
            return [
                "Dimensions": String(dimensions),
                "Metric": metric.rawValue,
            ]
        case .text(_, let mode):
            return mode.configurationDisplay
        case .spatial(_, let encoding, let level):
            return [
                "Encoding": encoding.rawValue,
                "Level": String(level),
            ]
        case .graph(let definition, _):
            return definition.configurationDisplay
        case .custom(let definition):
            var values = ["Identifier": definition.identifier]
            for (key, value) in definition.parameters {
                values["Parameter: \(key)"] = String(describing: value)
            }
            return values
        }
    }
}

private extension VersionHistoryStrategy {
    var displayText: String {
        switch self {
        case .keepAll: "Keep all"
        case .keepLast(let count): "Keep last \(count)"
        case .keepForDuration(let duration):
            "\(duration.seconds)s + \(duration.nanoseconds)ns"
        }
    }
}

private extension LeaderboardWindowType {
    var displayText: String {
        switch self {
        case .hourly: "Hourly"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .custom(let duration): "Custom (\(duration)s)"
        }
    }
}

private extension TextIndexMode {
    var configurationDisplay: [String: String] {
        switch self {
        case .fullText(
            let tokenizer,
            let storePositions,
            let ngramSize,
            let minimumTermLength
        ):
            return [
                "Tokenizer": tokenizer.rawValue,
                "Store Positions": storePositions ? "Yes" : "No",
                "N-gram Size": String(ngramSize),
                "Minimum Term Length": String(minimumTermLength),
            ]
        case .autocomplete(let minimum, let maximum):
            return [
                "Minimum Prefix Length": String(minimum),
                "Maximum Prefix Length": String(maximum),
            ]
        }
    }
}

private extension GraphIndexDefinition where FieldReference == FieldIdentity {
    var configurationDisplay: [String: String] {
        switch self {
        case .property(_, _, _, _, let strategy):
            return ["Strategy": strategy.rawValue]
        case .rdf:
            return [:]
        case .ontologyProjection(let iriBase, let graph):
            var values = ["Individual IRI Base": iriBase]
            if let graph {
                values["Graph"] = String(describing: graph.term)
            }
            return values
        }
    }
}

// MARK: - Field type presentation

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

// MARK: - Entity schema presentation

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
