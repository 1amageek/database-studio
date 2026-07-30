import Foundation
import AppKit
import UniformTypeIdentifiers

/// A record export format selected by the user.
public enum RecordExportFormat: String, CaseIterable, Identifiable, Sendable {
    case json = "JSON"
    case jsonLines = "JSONL"
    case csv = "CSV"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .json: return "json"
        case .jsonLines: return "jsonl"
        case .csv: return "csv"
        }
    }

    public var contentType: UTType? {
        switch self {
        case .json: return .json
        case .jsonLines: return UTType(filenameExtension: "jsonl")
        case .csv: return .commaSeparatedText
        }
    }
}

/// A deterministic failure encountered while encoding or writing an export.
public enum RecordExportError: LocalizedError, Sendable {
    case unavailableContentType(RecordExportFormat)
    case serializationFailed(RecordExportFormat, String)
    case recordSerializationFailed(String, RecordExportFormat, String)
    case textEncodingFailed(RecordExportFormat)
    case writeFailed(URL, String)

    public var errorDescription: String? {
        switch self {
        case .unavailableContentType(let format):
            return "No content type is registered for \(format.rawValue) exports."
        case .serializationFailed(let format, let message):
            return "Could not serialize the \(format.rawValue) export: \(message)"
        case .recordSerializationFailed(let identifier, let format, let message):
            return "Could not serialize record \(identifier) as \(format.rawValue): \(message)"
        case .textEncodingFailed(let format):
            return "Could not encode the \(format.rawValue) export as UTF-8."
        case .writeFailed(let destination, let message):
            return "Could not write the export to \(destination.path): \(message)"
        }
    }
}

/// Encodes database records in a user-selected format and writes the result.
public struct RecordExporter {

    // MARK: - Export Data Generation

    /// Encodes records as a JSON array.
    public static func encodeJSON(_ records: [StudioRecord]) throws -> Data {
        var exportedRecords: [[String: Any]] = []
        exportedRecords.reserveCapacity(records.count)

        for record in records {
            var exportedRecord = record.fields
            exportedRecord["_id"] = record.id
            exportedRecord["_type"] = record.typeName
            exportedRecords.append(exportedRecord)
        }

        do {
            return try JSONSerialization.data(
                withJSONObject: exportedRecords,
                options: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            throw RecordExportError.serializationFailed(.json, error.localizedDescription)
        }
    }

    /// Encodes records as newline-delimited JSON without a line-array copy.
    public static func encodeJSONLines(_ records: [StudioRecord]) throws -> Data {
        var output = Data()
        output.reserveCapacity(records.reduce(into: 0) { byteCount, record in
            byteCount += record.jsonByteCount + 1
        })

        for (index, record) in records.enumerated() {
            var exportedRecord = record.fields
            exportedRecord["_id"] = record.id
            exportedRecord["_type"] = record.typeName

            do {
                if index > 0 {
                    output.append(0x0A)
                }
                output.append(try JSONSerialization.data(withJSONObject: exportedRecord, options: [.sortedKeys]))
            } catch {
                throw RecordExportError.recordSerializationFailed(
                    record.id,
                    .jsonLines,
                    error.localizedDescription
                )
            }
        }

        return output
    }

    /// Encodes records as CSV.
    public static func encodeCSV(_ records: [StudioRecord], fields: [DiscoveredField]) throws -> Data {
        guard !records.isEmpty else { return Data() }

        var headers = ["_id", "_type"]
        let primitiveFields = fields.filter { field in
            switch field.inferredType {
            case .string, .number, .boolean:
                return true
            default:
                return false
            }
        }
        headers.append(contentsOf: primitiveFields.map(\.path))

        var output = Data()
        try append(headers.joined(separator: ","), to: &output, format: .csv)

        for record in records {
            var values: [String] = [
                escapedCSVField(record.id),
                escapedCSVField(record.typeName)
            ]
            values.reserveCapacity(primitiveFields.count + 2)

            for field in primitiveFields {
                let fieldValue = value(at: field.path, in: record.fields)
                values.append(escapedCSVField(csvFieldText(for: fieldValue)))
            }

            output.append(0x0A)
            try append(values.joined(separator: ","), to: &output, format: .csv)
        }

        return output
    }

    /// Encodes records using the selected export format.
    public static func encode(
        _ records: [StudioRecord],
        format: RecordExportFormat,
        fields: [DiscoveredField] = []
    ) throws -> Data {
        switch format {
        case .json:
            return try encodeJSON(records)
        case .jsonLines:
            return try encodeJSONLines(records)
        case .csv:
            return try encodeCSV(records, fields: fields)
        }
    }

    // MARK: - File Save Dialog

    @MainActor
    public static func selectExportDestination(
        suggestedName: String,
        format: RecordExportFormat
    ) throws -> URL? {
        guard let contentType = format.contentType else {
            throw RecordExportError.unavailableContentType(format)
        }
        let savePanel = NSSavePanel()
        savePanel.nameFieldLabel = "Export as:"
        savePanel.message = "Select location to save exported data"
        savePanel.allowedContentTypes = [contentType]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = "\(suggestedName).\(format.fileExtension)"

        guard savePanel.runModal() == .OK else { return nil }
        return savePanel.url
    }

    @MainActor
    @discardableResult
    public static func exportToSelectedDestination(
        records: [StudioRecord],
        typeName: String,
        format: RecordExportFormat,
        fields: [DiscoveredField] = []
    ) throws -> URL? {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let suggestedName = "\(typeName)_\(timestamp)"

        guard let destination = try selectExportDestination(suggestedName: suggestedName, format: format) else {
            return nil
        }

        let output = try encode(records, format: format, fields: fields)

        do {
            try output.write(to: destination)
            return destination
        } catch {
            throw RecordExportError.writeFailed(destination, error.localizedDescription)
        }
    }

    // MARK: - Export Value Serialization

    private static func escapedCSVField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func csvFieldText(for value: Any?) -> String {
        guard let value = value else { return "" }

        if value is NSNull {
            return ""
        } else if let string = value as? String {
            return string
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return "\(number)"
        } else {
            return String(describing: value)
        }
    }

    private static func value(at path: String, in fields: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = fields

        for component in components {
            guard let object = current as? [String: Any],
                  let nestedValue = object[component] else {
                return nil
            }
            current = nestedValue
        }

        return current
    }

    private static func append(
        _ string: String,
        to output: inout Data,
        format: RecordExportFormat
    ) throws {
        guard let bytes = string.data(using: .utf8) else {
            throw RecordExportError.textEncodingFailed(format)
        }
        output.append(bytes)
    }
}
