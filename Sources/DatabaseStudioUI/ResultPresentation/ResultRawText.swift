import DatabaseKit

/// Renders one canonical row for Raw with every value's kind, nested structure,
/// version bytes and annotations; it never substitutes a debug description.
enum ResultRawText {
    static func row(_ row: DatabaseKit.QueryRow, columns: [String]) -> String {
        var lines: [String] = []
        lines.reserveCapacity(row.values.count + 2)
        for (index, value) in row.values.enumerated() {
            let name = columns.indices.contains(index) ? columns[index] : "#\(index + 1)"
            lines.append(name + " = " + typed(value))
        }
        lines.append("version = " + (row.version.map { "bytes(" + ResultValueFormat.hex($0) + ")" } ?? "none"))
        lines.append("annotations = " + typed(.object(row.annotations)))
        return lines.joined(separator: "\n")
    }

    static func typed(_ value: DatabaseKit.QueryValue) -> String {
        switch value {
        case .primitive(let value): return typed(value)
        case .numeric: return "numeric(" + ResultValueFormat.text(value) + ")"
        case .json(let value):
            return "json(" + value.bytes.withUnsafeBytes { String(decoding: $0, as: UTF8.self) } + ")"
        case .jsonb(let value): return "jsonb(" + jsonb(value.root) + ")"
        case .array(let value):
            let shape = value.dimensions.map {
                "[\($0.lowerBound):\(Int64($0.lowerBound) + Int64($0.length) - 1)]"
            }.joined()
            return "array" + shape + "[" + value.elements.map(typed).joined(separator: ", ") + "]"
        case .composite(let value):
            return "row(" + value.fields.indices.map {
                value.type.columns[$0].name + ": " + typed(value.fields[$0])
            }.joined(separator: ", ") + ")"
        case .interval: return "interval(" + ResultValueFormat.text(value) + ")"
        case .time: return "time(" + ResultValueFormat.text(value) + ")"
        case .timeWithTimeZone: return "timetz(" + ResultValueFormat.text(value) + ")"
        case .dateInfinity: return "date(" + ResultValueFormat.text(value) + ")"
        case .timestampInfinity(_, let withTimeZone):
            return (withTimeZone ? "timestamptz(" : "timestamp(") + ResultValueFormat.text(value) + ")"
        case .intervalInfinity: return "interval(" + ResultValueFormat.text(value) + ")"
        }
    }

    static func typed(_ value: FieldValue) -> String {
        switch value {
        case .null: return "null"
        case .array(let values): return "[" + values.map(typed).joined(separator: ", ") + "]"
        case .object(let object):
            return "{" + object.fields.map { $0.key + ": " + typed($0.value) }.joined(separator: ", ") + "}"
        case .bytes(let bytes): return "bytes(" + ResultValueFormat.hex(bytes) + ")"
        case .string(let text): return "string(" + String(reflecting: text) + ")"
        default: return kind(value) + "(" + ResultValueFormat.text(value) + ")"
        }
    }

    private static func kind(_ value: FieldValue) -> String {
        switch value {
        case .null: "null"
        case .bool: "bool"
        case .int8: "int8"
        case .int16: "int16"
        case .int32: "int32"
        case .int64: "int64"
        case .uint8: "uint8"
        case .uint16: "uint16"
        case .uint32: "uint32"
        case .uint64: "uint64"
        case .float32: "float32"
        case .float64: "float64"
        case .decimal: "decimal"
        case .string: "string"
        case .bytes: "bytes"
        case .date: "date"
        case .time: "time"
        case .dateTime: "dateTime"
        case .timestamp: "timestamp"
        case .timeSpan: "timeSpan"
        case .calendarPeriod: "calendarPeriod"
        case .geographicPoint: "geographicPoint"
        case .geographicPosition: "geographicPosition"
        case .vector: "vector"
        case .uuid: "uuid"
        case .array: "array"
        case .object: "object"
        case .reference: "reference"
        case .rdfTerm: "rdfTerm"
        }
    }

    private static func jsonb(_ value: QueryJSONBNode) -> String {
        switch value {
        case .array(let values): "[" + values.indices.map { jsonb(values[$0]) }.joined(separator: ", ") + "]"
        case .object(let fields):
            "{" + fields.indices.map { String(reflecting: fields[$0].key) + ": " + jsonb(fields[$0].value) }
                .joined(separator: ", ") + "}"
        default: ResultValueFormat.jsonb(value)
        }
    }
}
