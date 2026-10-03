import Foundation
import CoreFoundation

struct AnalysisDatasetReader: AnalysisDatasetReading {
    enum Failure: LocalizedError {
        case capacity, format(String), identity(String), number(String)
        var errorDescription: String? {
            switch self {
            case .capacity: "Import supports files up to 32 MiB, 10,000 rows and 128 scalar columns per row."
            case .format(let detail): "Invalid dataset: " + detail
            case .identity(let value): "Empty or duplicate row identity: " + value
            case .number(let field): "Nonfinite or invalid numeric metric: " + field
            }
        }
    }
    static let maximumBytes = 32 * 1024 * 1024

    @concurrent func read(url: URL) async throws -> AnalysisDataset {
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        let data: Data
        do { data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data(); try handle.close() }
        catch { do { try handle.close() } catch { throw error }; throw error }
        return try decode(data: data, sourceName: url.lastPathComponent, format: url.pathExtension.lowercased())
    }

    func decode(data: Data, sourceName: String, format: String) throws -> AnalysisDataset {
        try Task.checkCancellation()
        guard data.count <= Self.maximumBytes else { throw Failure.capacity }
        var nodes: [GraphNode] = [], provenance: [String] = [], omitted = Set<String>(), declared = Set<String>()
        switch format {
        case "json":
            let value = try JSONSerialization.jsonObject(with: data)
            let envelope = value as? [String: Any]
            guard let rows = (envelope?["rows"] ?? value) as? [[String: Any]] else { throw Failure.format("Expected row objects or an object with a rows array.") }
            guard rows.count <= GraphNumericAnalyzer.maximumNodes else { throw Failure.capacity }
            for key in ["grain", "periodBasis", "publisher", "retrievalURL", "retrievedAt"] { if let text = envelope?[key] as? String { provenance.append(key + ": " + text) } }
            if let units = envelope?["units"] as? [String: String] { provenance += units.keys.sorted().map { $0 + ": " + units[$0]! } }
            if let limitations = envelope?["limitations"] as? [String] { provenance += limitations }
            for (index, row) in rows.enumerated() {
                try Task.checkCancellation()
                var metadata: [String: String] = [:], metrics: [String: Double] = [:]
                let id: String
                if let explicit = row["id"] { guard let text = explicit as? String else { throw Failure.identity("Row \(index + 1) requires a string id.") }; id = text }
                else { id = sourceName + ":row:" + String(index + 1) }
                let label = (row["label"] ?? row["name"] ?? row["company"]) as? String ?? id
                for (key, value) in row where key != "id" && key != "metrics" {
                    if let flags = value as? [String], key == "qualityFlags" { if !flags.isEmpty { metadata["Quality flags"] = flags.joined(separator: ", ") }; continue }
                    if value is NSNull { continue }
                    if let text = value as? String { metadata[key] = text }
                    else if let number = value as? NSNumber {
                        if CFGetTypeID(number) == CFBooleanGetTypeID() { metadata[key] = number.boolValue ? "true" : "false" }
                        else { guard number.doubleValue.isFinite else { throw Failure.number(key) }; metrics[key] = number.doubleValue; declared.insert(key) }
                    } else { omitted.insert(key) }
                }
                if let raw = row["metrics"] {
                    guard let table = raw as? [String: Any] else { throw Failure.format("metrics must be an object.") }
                    for (key, value) in table {
                        declared.insert(key)
                        if value is NSNull { continue }
                        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { throw Failure.number(key) }
                        guard metrics[key] == nil, metadata[key] == nil else { throw Failure.format("Duplicate metric column: " + key) }
                        metrics[key] = number.doubleValue
                    }
                }
                guard metadata.count + declared.count <= 128 else { throw Failure.capacity }
                nodes.append(GraphNode(id: id, label: label, role: .instance, metadata: metadata, metrics: metrics))
            }
        case "csv":
            guard let text = String(data: data, encoding: .utf8) else { throw Failure.format("CSV must be UTF-8.") }
            let records = try csv(text)
            guard let header = records.first, !header.isEmpty, header.allSatisfy({ !$0.isEmpty }), Set(header).count == header.count else { throw Failure.format("Column names must be nonempty and unique.") }
            guard header.count <= 128, records.count - 1 <= GraphNumericAnalyzer.maximumNodes else { throw Failure.capacity }
            let rows = records.dropFirst()
            guard !rows.isEmpty, rows.allSatisfy({ $0.count == header.count }) else { throw Failure.format("Every row must match the header width.") }
            let numeric = header.indices.filter { index in
                header[index] != "id" && !["label", "name", "company"].contains(header[index]) && rows.contains(where: { !$0[index].isEmpty }) && rows.allSatisfy { $0[index].isEmpty || Double($0[index]) != nil }
            }
            declared = Set(numeric.map { header[$0] })
            let identityColumn = header.firstIndex(of: "id")
            let labelColumn = ["label", "name", "company"].compactMap { header.firstIndex(of: $0) }.first
            for (index, row) in rows.enumerated() {
                try Task.checkCancellation()
                let id = identityColumn.map { row[$0] } ?? sourceName + ":row:" + String(index + 1)
                var metrics: [String: Double] = [:], metadata: [String: String] = [:]
                for column in header.indices where !row[column].isEmpty {
                    if numeric.contains(column) {
                        guard let value = Double(row[column]), value.isFinite else { throw Failure.number(header[column]) }
                        metrics[header[column]] = value
                    } else if column != identityColumn { metadata[header[column]] = row[column] }
                }
                nodes.append(GraphNode(id: id, label: labelColumn.map { row[$0] }.flatMap { $0.isEmpty ? nil : $0 } ?? id, role: .instance, metadata: metadata, metrics: metrics))
            }
            provenance.append("Numeric columns inferred from finite numeric text. Units and reporting periods are not inferred.")
        default: throw Failure.format("Choose a CSV or JSON file.")
        }
        guard !nodes.isEmpty else { throw Failure.format("The dataset has no rows.") }
        var identities = Set<String>()
        for node in nodes { guard !node.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, identities.insert(node.id).inserted else { throw Failure.identity(node.id) } }
        let columns = declared.sorted()
        guard !columns.isEmpty else { throw Failure.format("The dataset has no numeric columns.") }
        let missing = Dictionary(uniqueKeysWithValues: columns.map { key in (key, nodes.reduce(0) { $0 + ($1.metrics[key] == nil ? 1 : 0) }) })
        var warnings: [String] = []
        let flagged = nodes.filter { $0.metadata["Quality flags"] != nil }.count
        if flagged > 0 { warnings.append("\(flagged) rows have source quality flags.") }
        let numericLabels = nodes.filter { Double($0.label) != nil }.count
        if numericLabels > 0 { warnings.append("\(numericLabels) labels are entirely numeric; verify their identity if names were expected.") }
        if !omitted.isEmpty { warnings.append("Nested non-scalar columns omitted: " + omitted.sorted().joined(separator: ", ")) }
        return AnalysisDataset(document: GraphDocument(nodes: nodes), sourceName: sourceName, provenance: provenance,
                               warnings: warnings, numericColumns: columns, missingCounts: missing)
    }

    private func csv(_ input: String) throws -> [[String]] {
        let text = input.hasPrefix("\u{feff}") ? String(input.dropFirst()) : input
        var commas = 0, semicolons = 0, headerQuoted = false
        for character in text {
            if character == "\"" { headerQuoted.toggle() }
            if !headerQuoted {
                if character == "\n" || character == "\r" || character == "\r\n" { break }
                if character == "," { commas += 1 }
                if character == ";" { semicolons += 1 }
            }
        }
        let separator: Character = semicolons > commas ? ";" : ","
        var rows: [[String]] = [], fields: [String] = [], field = "", quoted = false, closedQuote = false
        var cursor = text.startIndex
        func appendField() throws {
            guard fields.count < 128 else { throw Failure.capacity }
            fields.append(field.trimmingCharacters(in: .whitespaces)); field = ""; closedQuote = false
        }
        while cursor < text.endIndex {
            let character = text[cursor]; cursor = text.index(after: cursor)
            if quoted {
                if character == "\"" {
                    if cursor < text.endIndex, text[cursor] == "\"" { field.append("\""); cursor = text.index(after: cursor) }
                    else { quoted = false; closedQuote = true }
                } else { field.append(character) }
            } else if character == separator { try appendField() }
            else if character == "\n" || character == "\r" || character == "\r\n" {
                try appendField(); if fields.count > 1 || !fields[0].isEmpty { rows.append(fields) }; fields = []
                guard rows.count <= GraphNumericAnalyzer.maximumNodes + 1 else { throw Failure.capacity }
                try Task.checkCancellation()
            } else if character == "\"" {
                guard field.isEmpty, !closedQuote else { throw Failure.format("Unexpected quote in CSV.") }; quoted = true
            } else {
                guard !closedQuote || character.isWhitespace else { throw Failure.format("Text follows a closing CSV quote.") }
                if !closedQuote { field.append(character) }
            }
        }
        guard !quoted else { throw Failure.format("Unterminated CSV quote.") }
        if !field.isEmpty || !fields.isEmpty || closedQuote { try appendField(); rows.append(fields) }
        return rows
    }
}
