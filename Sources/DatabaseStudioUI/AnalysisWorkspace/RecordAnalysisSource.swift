import Foundation
import DatabaseKit
import DatabaseWire

/// Projects an immutable server result page for analysis without changing canonical values.
struct RecordAnalysisSource: Sendable {
    enum Failure: LocalizedError {
        case capacity, invalidColumns, invalidRow, invalidMeasurement(String), nonfinite(String), noMeasurements
        var errorDescription: String? {
            switch self {
            case .capacity: "Analysis supports 10,000 rows, 128 scalar fields per row, eight nested levels and 32 MiB of scalar text."
            case .invalidColumns: "The result contains ambiguous or empty column names."
            case .invalidRow: "The result contains a row with an invalid column count or ambiguous field paths."
            case .invalidMeasurement(let path): "The result contains a malformed numeric RDF literal at " + path
            case .nonfinite(let path): "The result contains a nonfinite measurement at " + path
            case .noMeasurements: "This page contains no supported numeric measurements."
            }
        }
    }
    let columns: [QueryColumn]
    let rows: [DatabaseWire.QueryRow]
    let hasNextPage: Bool

    @concurrent func dataset() async throws -> AnalysisDataset {
        guard rows.count <= 10_000, columns.count <= 128 else { throw Failure.capacity }
        guard columns.allSatisfy({ !$0.name.isEmpty }), Set(columns.map(\.name)).count == columns.count else { throw Failure.invalidColumns }
        var nodes: [GraphNode] = [], numericKeys = Set<String>(), omitted = Set<String>(), approximate = Set<String>()
        var textBytes = 0
        for (index, row) in rows.enumerated() {
            try Task.checkCancellation()
            guard row.values.count == columns.count else { throw Failure.invalidRow }
            var metrics: [String: Double] = [:], metadata: [String: String] = [:], seen = Set<String>()
            var stack = zip(columns, row.values).map { ("/" + escaped($0.0.name), $0.1, 0) }
            var visited = 0
            while let (path, value, depth) = stack.popLast() {
                visited += 1
                guard visited <= 128, depth <= 8 else { throw Failure.capacity }
                guard seen.insert(path).inserted else { throw Failure.invalidRow }
                textBytes += path.utf8.count
                switch value {
                case .object(let object):
                    guard visited + stack.count + object.count <= 128 else { throw Failure.capacity }
                    for field in object.fields { stack.append((path + "/" + escaped(field.key), field.value, depth + 1)) }
                case .null: break
                case .bool(let value): metadata[path] = value ? "true" : "false"
                case .string(let value): metadata[path] = value; textBytes += value.utf8.count
                case .int8(let value): metrics[path] = Double(value)
                case .int16(let value): metrics[path] = Double(value)
                case .int32(let value): metrics[path] = Double(value)
                case .uint8(let value): metrics[path] = Double(value)
                case .uint16(let value): metrics[path] = Double(value)
                case .uint32(let value): metrics[path] = Double(value)
                case .int64(let value):
                    let converted = Double(value)
                    if Int64(exactly: converted) == value { metrics[path] = converted } else { omitted.insert(path + " (integer precision)") }
                case .uint64(let value):
                    let converted = Double(value)
                    if UInt64(exactly: converted) == value { metrics[path] = converted } else { omitted.insert(path + " (integer precision)") }
                case .float32(let value): metrics[path] = Double(value)
                case .float64(let value): metrics[path] = value
                case .decimal(let value):
                    let converted = Double(value.coefficient) * pow(10, -Double(value.scale))
                    guard converted.isFinite, value.coefficient == 0 || converted != 0 else { throw Failure.nonfinite(path) }
                    metrics[path] = converted; approximate.insert(path)
                case .array, .bytes, .vector: omitted.insert(path)
                case .rdfTerm(.literal(let literal)):
                    textBytes += literal.lexicalForm.utf8.count + literal.datatypeIRI.rawValue.utf8.count
                    let datatype = literal.datatypeIRI.rawValue
                    let xsd = "http://www.w3.org/2001/XMLSchema#"
                    if [xsd + "integer", xsd + "decimal", xsd + "float", xsd + "double"].contains(datatype) {
                        let lexical = literal.lexicalForm.trimmingCharacters(in: .whitespacesAndNewlines)
                        let pattern = datatype == xsd + "integer" ? "^[+-]?[0-9]+$" :
                            "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)" + (datatype == xsd + "decimal" ? "$" : "(?:[eE][+-]?[0-9]+)?$")
                        guard lexical.range(of: pattern, options: .regularExpression) != nil else {
                            throw Failure.invalidMeasurement(path)
                        }
                        if datatype == xsd + "integer" {
                            if let integer = Int128(lexical), let value = Double(lexical), Int128(exactly: value) == integer {
                                metrics[path] = value
                            } else { omitted.insert(path + " (integer precision)") }
                        } else {
                            guard let value = Double(lexical), value.isFinite else { throw Failure.nonfinite(path) }
                            if datatype == xsd + "decimal" {
                                guard value != 0 || !lexical.utf8.contains(where: { $0 >= 49 && $0 <= 57 }) else { throw Failure.nonfinite(path) }
                                approximate.insert(path)
                            }
                            metrics[path] = value
                        }
                    } else if datatype == xsd + "string" || literal.languageTag != nil {
                        metadata[path] = literal.lexicalForm
                    } else { metadata[path] = literal.description }
                default:
                    let text = String(describing: value); metadata[path] = text; textBytes += text.utf8.count
                }
                if let measurement = metrics[path], !measurement.isFinite { throw Failure.nonfinite(path) }
                guard textBytes <= 32 * 1024 * 1024 else { throw Failure.capacity }
            }
            numericKeys.formUnion(metrics.keys)
            nodes.append(GraphNode(id: "page-row:\(index)", label: "Row \(index + 1)", role: .instance, metadata: metadata, metrics: metrics))
        }
        guard !numericKeys.isEmpty else { throw Failure.noMeasurements }
        let keys = numericKeys.sorted()
        var warnings: [String] = []
        if !omitted.isEmpty { warnings.append("Excluded unsupported or inexact scalar fields: " + omitted.sorted().joined(separator: ", ")) }
        if !approximate.isEmpty { warnings.append("Decimal values use approximate Double coordinates; original exact values remain in Table/Raw: " + approximate.sorted().joined(separator: ", ")) }
        return AnalysisDataset(document: GraphDocument(nodes: nodes), sourceName: "Result Page",
            provenance: ["Read-only snapshot of the current authenticated result page.",
                         hasNextPage ? "More rows exist. This analysis covers this page only." : "This response has no continuation. No additional records were fetched.",
                         "Field paths use JSON Pointer escaping. Nulls and unsupported values are not replaced by zero.",
                         "Page row identity is local to this response; it is not a persisted record identifier."],
            warnings: warnings, numericColumns: keys,
            missingCounts: Dictionary(uniqueKeysWithValues: keys.map { key in (key, nodes.filter { $0.metrics[key] == nil }.count) }))
    }

    private func escaped(_ key: String) -> String { key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }

    static func rowIndex(_ id: String) -> Int? {
        guard id.hasPrefix("page-row:") else { return nil }
        return Int(id.dropFirst("page-row:".count))
    }
}
