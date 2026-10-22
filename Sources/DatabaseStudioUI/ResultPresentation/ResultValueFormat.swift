import Foundation
import DatabaseKit

/// Human-readable values are supplemental to, never replacements for, canonical fields.
enum ResultValueFormat {
    static func text(_ value: DatabaseKit.QueryValue) -> String {
        switch value {
        case .primitive(let value): return text(value)
        case .numeric(let value): return numeric(value)
        case .json(let value): return "JSON · \(value.bytes.count) bytes"
        case .jsonb(let value): return "JSONB · " + jsonb(value.root)
        case .array(let value):
            let shape = value.dimensions.map { "[\($0.lowerBound):\(Int64($0.lowerBound) + Int64($0.length) - 1)]" }.joined()
            return "\(value.elements.count) elements · " + shape
        case .composite(let value): return "\(value.fields.count) fields"
        case .interval(let value): return "\(value.period.months) months \(value.period.days) days \(value.microseconds) µs"
        case .time(let value): return time(value)
        case .timeWithTimeZone(let value):
            let offset = Int64(value.utcOffsetSeconds), magnitude = abs(Int64(value.utcOffsetSeconds))
            return time(value.time) + (offset < 0 ? "-" : "+") + padded(magnitude / 3600, 2)
                + ":" + padded(magnitude / 60 % 60, 2) + ":" + padded(magnitude % 60, 2)
        case .dateInfinity(let sign), .timestampInfinity(let sign, _), .intervalInfinity(let sign):
            return sign == .negative ? "-infinity" : "infinity"
        }
    }

    static func jsonb(_ value: QueryJSONBNode) -> String {
        switch value {
        case .null: "null"
        case .bool(let value): value ? "true" : "false"
        case .string(let value): String(reflecting: value)
        case .number(let value): numeric(value)
        case .array(let values): "\(values.count) elements"
        case .object(let values): "\(values.count) fields"
        }
    }

    private static func numeric(_ value: QueryNumericValue) -> String {
        let decimal = value.value
        var result = text(FieldValue.decimal(decimal))
        guard (0...12).contains(value.displayScale), (-12...12).contains(decimal.scale) else {
            return result + " (scale \(value.displayScale))"
        }
        if value.displayScale > 0 {
            if !result.contains(".") { result += "." }
            let count = result.split(separator: ".", omittingEmptySubsequences: false).last?.count ?? 0
            result += String(repeating: "0", count: max(0, Int(value.displayScale) - count))
        }
        return result
    }

    private static func time(_ value: QueryTimeValue) -> String {
        let micros = value.microsecondsSinceMidnight, seconds = micros / 1_000_000
        return padded(seconds / 3600, 2) + ":" + padded(seconds / 60 % 60, 2)
            + ":" + padded(seconds % 60, 2) + "." + padded(micros % 1_000_000, 6)
    }

    private static func padded(_ value: Int64, _ count: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, count - text.count)) + text
    }

    static func isNumeric(_ value: DatabaseKit.QueryValue) -> Bool {
        switch value {
        case .numeric: true
        case .primitive(let value): isNumeric(value)
        default: false
        }
    }

    static func text(_ value: FieldValue) -> String {
        switch value {
        case .null: return "NULL"
        case .bool(let value): return value ? "true" : "false"
        case .int8(let value): return value.formatted()
        case .int16(let value): return value.formatted()
        case .int32(let value): return value.formatted()
        case .int64(let value): return value.formatted()
        case .uint8(let value): return value.formatted()
        case .uint16(let value): return value.formatted()
        case .uint32(let value): return value.formatted()
        case .uint64(let value): return value.formatted()
        case .float32(let value): return String(value)
        case .float64(let value): return String(value)
        case .string(let value): return value
        case .decimal(let value):
            guard (-12...12).contains(value.scale) else { return "\(value.coefficient)e\(-Int64(value.scale))" }
            let negative = value.coefficient < 0
            var digits = String(value.coefficient.magnitude)
            if value.scale > 0 {
                let scale = Int(value.scale)
                if digits.count <= scale { digits = String(repeating: "0", count: scale + 1 - digits.count) + digits }
                digits.insert(".", at: digits.index(digits.endIndex, offsetBy: -scale))
            } else if value.scale < 0 { digits += String(repeating: "0", count: -Int(value.scale)) }
            return (negative ? "-" : "") + digits
        case .array(let values): return "\(values.count) elements"
        case .object(let value): return "\(value.count) fields"
        case .bytes(let value): return "\(value.count) bytes"
        case .rdfTerm(let value): return value.description
        default: return String(describing: value)
        }
    }

    static func isNumeric(_ value: FieldValue) -> Bool {
        switch value {
        case .int8, .int16, .int32, .int64, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .decimal: true
        default: false
        }
    }
}
