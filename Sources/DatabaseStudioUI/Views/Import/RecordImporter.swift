import Foundation
import AppKit
import UniformTypeIdentifiers

/// A record import format selected by the user.
public enum RecordImportFormat: String, CaseIterable, Sendable {
    case json = "JSON"
    case jsonLines = "JSONL"
    case csv = "CSV"
}

/// Parsed records and source metadata for a selected import file.
@MainActor
public struct ParsedRecordImport {
    public let records: [[String: Any]]
    public let format: RecordImportFormat
    public let sourceURL: URL
    public let recordCount: Int

    public init(records: [[String: Any]], format: RecordImportFormat, sourceURL: URL) {
        self.records = records
        self.format = format
        self.sourceURL = sourceURL
        self.recordCount = records.count
    }
}

/// A deterministic failure encountered while reading a record import file.
public enum RecordImportError: LocalizedError, Sendable {
    case fileNotFound
    case invalidFormat(String)
    case parseError(String)
    case emptyFile
    case unsupportedFormat
    case unavailableContentType(RecordImportFormat)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .invalidFormat(let detail):
            return "Invalid format: \(detail)"
        case .parseError(let detail):
            return "Parse error: \(detail)"
        case .emptyFile:
            return "File is empty"
        case .unsupportedFormat:
            return "Unsupported file format"
        case .unavailableContentType(let format):
            return "No content type is registered for \(format.rawValue) imports"
        }
    }
}

/// Reads and parses record import files selected by the user.
@MainActor
public struct RecordImporter {

    // MARK: - File Open Dialog

    /// Presents the record import file picker.
    @MainActor
    public static func selectImportSource() throws -> URL? {
        guard let jsonLinesContentType = UTType(filenameExtension: "jsonl") else {
            throw RecordImportError.unavailableContentType(.jsonLines)
        }
        let panel = NSOpenPanel()
        panel.message = "Select a file to import"
        panel.allowedContentTypes = [.json, .commaSeparatedText, jsonLinesContentType]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - Parse Files

    /// Reads and parses a record import file.
    public static func parseRecords(at url: URL) async throws -> ParsedRecordImport {
        let data = try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw RecordImportError.fileNotFound
            }
            return try Data(contentsOf: url)
        }.value
        guard !data.isEmpty else {
            throw RecordImportError.emptyFile
        }

        let fileExtension = url.pathExtension.lowercased()

        switch fileExtension {
        case "json":
            return try parseJSONRecords(data: data, sourceURL: url)
        case "jsonl":
            return try parseJSONLines(data: data, sourceURL: url)
        case "csv":
            return try parseCSVRecords(data: data, sourceURL: url)
        default:
            throw RecordImportError.unsupportedFormat
        }
    }

    /// Parses a JSON record or record array.
    private static func parseJSONRecords(data: Data, sourceURL: URL) throws -> ParsedRecordImport {
        let jsonValue = try JSONSerialization.jsonObject(with: data, options: [])

        if let records = jsonValue as? [[String: Any]] {
            guard !records.isEmpty else {
                throw RecordImportError.emptyFile
            }
            return ParsedRecordImport(records: records, format: .json, sourceURL: sourceURL)
        } else if let record = jsonValue as? [String: Any] {
            return ParsedRecordImport(records: [record], format: .json, sourceURL: sourceURL)
        } else {
            throw RecordImportError.invalidFormat("JSON must be an array of objects or a single object")
        }
    }

    /// Parses newline-delimited JSON records.
    private static func parseJSONLines(data: Data, sourceURL: URL) throws -> ParsedRecordImport {
        var records: [[String: Any]] = []
        var lineStart = data.startIndex
        var lineNumber = 1
        var index = data.startIndex

        while index < data.endIndex {
            let byte = data[index]
            if byte == 0x0A || byte == 0x0D {
                try appendJSONRecord(
                    from: data[lineStart..<index],
                    lineNumber: lineNumber,
                    to: &records
                )

                let nextIndex = data.index(after: index)
                if byte == 0x0D,
                   nextIndex < data.endIndex,
                   data[nextIndex] == 0x0A {
                    index = nextIndex
                }
                lineStart = data.index(after: index)
                lineNumber += 1
            }
            index = data.index(after: index)
        }

        if lineStart < data.endIndex {
            try appendJSONRecord(
                from: data[lineStart..<data.endIndex],
                lineNumber: lineNumber,
                to: &records
            )
        }

        guard !records.isEmpty else {
            throw RecordImportError.emptyFile
        }

        return ParsedRecordImport(records: records, format: .jsonLines, sourceURL: sourceURL)
    }

    /// Parses records from CSV rows.
    private static func parseCSVRecords(data: Data, sourceURL: URL) throws -> ParsedRecordImport {
        guard let content = String(data: data, encoding: .utf8) else {
            throw RecordImportError.invalidFormat("Invalid UTF-8 encoding")
        }

        var headers: [String]?
        var records: [[String: Any]] = []

        try readCSVRows(in: content) { rowNumber, values in
            if values.count == 1,
               values[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }

            guard let existingHeaders = headers else {
                guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
                    throw RecordImportError.invalidFormat("CSV header fields must not be empty")
                }
                headers = values
                return
            }

            guard values.count == existingHeaders.count else {
                throw RecordImportError.invalidFormat(
                    "CSV row \(rowNumber) has \(values.count) fields; expected \(existingHeaders.count)"
                )
            }

            var record: [String: Any] = [:]
            record.reserveCapacity(existingHeaders.count)

            for (index, header) in existingHeaders.enumerated() {
                record[header] = inferredValue(from: values[index])
            }
            records.append(record)
        }

        guard headers != nil else {
            throw RecordImportError.emptyFile
        }
        guard !records.isEmpty else {
            throw RecordImportError.invalidFormat("CSV must have a header row and at least one data row")
        }

        return ParsedRecordImport(records: records, format: .csv, sourceURL: sourceURL)
    }

    // MARK: - JSON Lines

    private static func appendJSONRecord(
        from line: Data.SubSequence,
        lineNumber: Int,
        to records: inout [[String: Any]]
    ) throws {
        guard let contentRange = nonWhitespaceRange(in: line) else { return }

        do {
            let jsonValue = try JSONSerialization.jsonObject(with: line[contentRange], options: [])
            guard let record = jsonValue as? [String: Any] else {
                throw RecordImportError.parseError("Line \(lineNumber) is not a JSON object")
            }
            records.append(record)
        } catch let importError as RecordImportError {
            throw importError
        } catch {
            throw RecordImportError.parseError("Line \(lineNumber): \(error.localizedDescription)")
        }
    }

    private static func nonWhitespaceRange(in data: Data.SubSequence) -> Range<Data.Index>? {
        var lowerBound = data.startIndex
        while lowerBound < data.endIndex, isJSONWhitespace(data[lowerBound]) {
            lowerBound = data.index(after: lowerBound)
        }
        guard lowerBound < data.endIndex else { return nil }

        var upperBound = data.endIndex
        repeat {
            upperBound = data.index(before: upperBound)
        } while upperBound > lowerBound && isJSONWhitespace(data[upperBound])

        return lowerBound..<data.index(after: upperBound)
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09
    }

    // MARK: - CSV Rows

    private static func readCSVRows(
        in content: String,
        consume: (Int, [String]) throws -> Void
    ) throws {
        var row: [String] = []
        var field = ""
        var fieldWasQuoted = false
        var isInsideQuotedField = false
        var rowNumber = 1
        var index = content.startIndex

        func completedField() -> String {
            fieldWasQuoted ? field : field.trimmingCharacters(in: .whitespaces)
        }

        while index < content.endIndex {
            let character = content[index]
            let nextIndex = content.index(after: index)

            if character == "\"" {
                if isInsideQuotedField {
                    if nextIndex < content.endIndex, content[nextIndex] == "\"" {
                        field.append("\"")
                        index = content.index(after: nextIndex)
                        continue
                    }
                    isInsideQuotedField = false
                } else if field.isEmpty {
                    isInsideQuotedField = true
                    fieldWasQuoted = true
                } else {
                    field.append(character)
                }
            } else if character == "," && !isInsideQuotedField {
                row.append(completedField())
                field = ""
                fieldWasQuoted = false
            // "\r\n" is one Character (grapheme cluster) in Swift, so CRLF
            // never matches "\r" or "\n" alone and must be listed explicitly.
            } else if (character == "\n" || character == "\r" || character == "\r\n") && !isInsideQuotedField {
                row.append(completedField())
                try consume(rowNumber, row)
                row.removeAll(keepingCapacity: true)
                field = ""
                fieldWasQuoted = false
                rowNumber += 1

                if character == "\r", nextIndex < content.endIndex, content[nextIndex] == "\n" {
                    index = content.index(after: nextIndex)
                    continue
                }
            } else {
                field.append(character)
            }

            index = nextIndex
        }

        guard !isInsideQuotedField else {
            throw RecordImportError.invalidFormat("CSV row \(rowNumber) has an unterminated quoted field")
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(completedField())
            try consume(rowNumber, row)
        }
    }

    private static func inferredValue(from string: String) -> Any {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        // Empty value.
        if trimmed.isEmpty {
            return NSNull()
        }

        // Boolean.
        if trimmed.lowercased() == "true" {
            return true
        }
        if trimmed.lowercased() == "false" {
            return false
        }

        // Integer.
        if let intValue = Int(trimmed) {
            return intValue
        }

        // Floating-point number.
        if let doubleValue = Double(trimmed) {
            return doubleValue
        }

        // String.
        return trimmed
    }
}
