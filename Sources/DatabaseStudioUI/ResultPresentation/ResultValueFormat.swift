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
        case .date(let value): return date(value)
        case .time(let value): return time(value)
        case .dateTime(let value): return date(value.date) + "T" + time(value.time)
        case .timestamp(let value): return timestamp(value)
        case .timeSpan(let value): return timeSpan(value)
        case .calendarPeriod(let value): return "\(value.months) months \(value.days) days"
        case .geographicPoint(let value): return point(value)
        case .geographicPosition(let value): return point(value.point) + " · \(value.ellipsoidalHeightInMeters) m"
        case .vector(let value): return "\(value.count) × \(value.elementType) vector"
        case .uuid(let value): return value.description
        case .reference(let value): return value.entity + " · " + identifier(value.id)
        }
    }

    /// Exact lowercase hexadecimal bytes, used for opaque versions and identifiers.
    static func hex(_ bytes: ByteString) -> String {
        let digits = Array("0123456789abcdef")
        var text = ""
        text.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0f)])
        }
        return text.isEmpty ? "empty" : text
    }

    private static func date(_ value: CivilDate) -> String {
        year(Int64(value.year)) + "-" + padded(Int64(value.month), 2) + "-" + padded(Int64(value.day), 2)
    }

    private static func time(_ value: CivilTime) -> String {
        padded(Int64(value.hour), 2) + ":" + padded(Int64(value.minute), 2) + ":"
            + padded(Int64(value.second), 2) + fraction(value.nanoseconds)
    }

    /// Renders the UTC instant in ISO 8601 form using the proleptic Gregorian calendar.
    private static func timestamp(_ value: Timestamp) -> String {
        let seconds = value.secondsSinceUnixEpoch
        let days = seconds >= 0 ? seconds / 86_400 : -((-(seconds + 1)) / 86_400) - 1
        let secondOfDay = seconds - days * 86_400
        // Civil-from-days conversion (Howard Hinnant), valid for the full Int64 day range.
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return self.year(year) + "-" + padded(month, 2) + "-" + padded(day, 2) + "T"
            + padded(secondOfDay / 3_600, 2) + ":" + padded(secondOfDay / 60 % 60, 2) + ":"
            + padded(secondOfDay % 60, 2) + fraction(value.nanoseconds) + "Z"
    }

    /// Floor-represented spans render their signed exact value in seconds.
    private static func timeSpan(_ value: TimeSpan) -> String {
        if value.seconds < 0, value.nanoseconds > 0 {
            let whole = (value.seconds + 1).magnitude
            return "-" + String(whole) + fraction(1_000_000_000 - value.nanoseconds) + " s"
        }
        return String(value.seconds) + fraction(value.nanoseconds) + " s"
    }

    private static func point(_ value: GeographicPoint) -> String {
        "\(value.latitude), \(value.longitude)"
    }

    private static func identifier(_ value: ReferenceIdentifier) -> String {
        switch value {
        case .bool(let value): value ? "true" : "false"
        case .int8(let value): String(value)
        case .int16(let value): String(value)
        case .int32(let value): String(value)
        case .int64(let value): String(value)
        case .uint8(let value): String(value)
        case .uint16(let value): String(value)
        case .uint32(let value): String(value)
        case .uint64(let value): String(value)
        case .string(let value): value
        case .bytes(let value): hex(value)
        case .uuid(let value): value.description
        case .composite(let values): "(" + values.map(identifier).joined(separator: ", ") + ")"
        }
    }

    private static func year(_ value: Int64) -> String {
        (value < 0 ? "-" : "") + padded(Int64(value.magnitude), 4)
    }

    /// Exact fractional seconds without trailing zeros; whole seconds render none.
    private static func fraction(_ nanoseconds: UInt32) -> String {
        guard nanoseconds > 0 else { return "" }
        var digits = padded(Int64(nanoseconds), 9)
        while digits.last == "0" { digits.removeLast() }
        return "." + digits
    }

    static func isNumeric(_ value: FieldValue) -> Bool {
        switch value {
        case .int8, .int16, .int32, .int64, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .decimal: true
        default: false
        }
    }
}
