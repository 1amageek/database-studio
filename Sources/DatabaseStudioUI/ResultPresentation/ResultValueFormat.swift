import Foundation
import DatabaseKit

/// Human-readable values are supplemental to, never replacements for, canonical fields.
enum ResultValueFormat {
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
