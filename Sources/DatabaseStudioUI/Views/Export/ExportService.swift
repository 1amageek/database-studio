import Foundation
import AppKit
import UniformTypeIdentifiers

/// エクスポートフォーマット
public enum ExportFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case jsonl = "JSONL"
    case csv = "CSV"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .json: return "json"
        case .jsonl: return "jsonl"
        case .csv: return "csv"
        }
    }

    public var utType: UTType {
        switch self {
        case .json: return .json
        case .jsonl: return UTType(filenameExtension: "jsonl") ?? .plainText
        case .csv: return .commaSeparatedText
        }
    }
}

/// エクスポートサービス
public struct ExportService {

    // MARK: - Export Data Generation

    /// ItemsをJSON配列形式でエクスポート
    public static func exportAsJSON(_ items: [DecodedItem]) -> Data {
        var jsonArray: [[String: Any]] = []

        for item in items {
            var record = item.fields
            record["_id"] = item.id
            record["_type"] = item.typeName
            jsonArray.append(record)
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: jsonArray,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return Data()
        }

        return data
    }

    /// ItemsをJSONL形式でエクスポート（1行1JSON）
    public static func exportAsJSONL(_ items: [DecodedItem]) -> Data {
        var lines: [String] = []

        for item in items {
            var record = item.fields
            record["_id"] = item.id
            record["_type"] = item.typeName

            if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
               let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    /// ItemsをCSV形式でエクスポート
    public static func exportAsCSV(_ items: [DecodedItem], fields: [DiscoveredField]) -> Data {
        guard !items.isEmpty else { return Data() }

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

        var rows: [String] = [headers.joined(separator: ",")]

        for item in items {
            var values: [String] = [
                escapeCSV(item.id),
                escapeCSV(item.typeName)
            ]

            for field in primitiveFields {
                let value = resolveFieldPath(field.path, in: item.fields)
                values.append(escapeCSV(formatValue(value)))
            }

            rows.append(values.joined(separator: ","))
        }

        return rows.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    /// 指定フォーマットでエクスポート
    public static func export(_ items: [DecodedItem], format: ExportFormat, fields: [DiscoveredField] = []) -> Data {
        switch format {
        case .json:
            return exportAsJSON(items)
        case .jsonl:
            return exportAsJSONL(items)
        case .csv:
            return exportAsCSV(items, fields: fields)
        }
    }

    // MARK: - File Save Dialog

    @MainActor
    public static func showSaveDialog(
        suggestedName: String,
        format: ExportFormat
    ) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldLabel = "Export as:"
        panel.message = "Select location to save exported data"
        panel.allowedContentTypes = [format.utType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(suggestedName).\(format.fileExtension)"

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    public static func exportAndSave(
        items: [DecodedItem],
        typeName: String,
        format: ExportFormat,
        fields: [DiscoveredField] = []
    ) -> Bool {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let suggestedName = "\(typeName)_\(timestamp)"

        guard let url = showSaveDialog(suggestedName: suggestedName, format: format) else {
            return false
        }

        let data = export(items, format: format, fields: fields)

        do {
            try data.write(to: url)
            return true
        } catch {
            print("Failed to export: \(error)")
            return false
        }
    }

    // MARK: - Private Helpers

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func formatValue(_ value: Any?) -> String {
        guard let value = value else { return "" }

        if value is NSNull {
            return ""
        } else if let str = value as? String {
            return str
        } else if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue ? "true" : "false"
            }
            return "\(num)"
        } else {
            return String(describing: value)
        }
    }

    private static func resolveFieldPath(_ path: String, in json: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = json

        for component in components {
            guard let dict = current as? [String: Any],
                  let next = dict[component] else {
                return nil
            }
            current = next
        }

        return current
    }
}
