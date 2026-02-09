import Foundation
import AppKit
import UniformTypeIdentifiers

/// インポートフォーマット
public enum ImportFormat: String, CaseIterable, Sendable {
    case json = "JSON"
    case jsonl = "JSONL"
    case csv = "CSV"
}

/// インポート結果
public struct ImportResult {
    public let recordsData: Data
    public let format: ImportFormat
    public let sourceURL: URL
    public let recordCount: Int

    public var count: Int { recordCount }

    public init(records: [[String: Any]], format: ImportFormat, sourceURL: URL) throws {
        self.recordsData = try JSONSerialization.data(withJSONObject: records, options: [])
        self.format = format
        self.sourceURL = sourceURL
        self.recordCount = records.count
    }

    public func getRecords() -> [[String: Any]] {
        guard let records = try? JSONSerialization.jsonObject(with: recordsData) as? [[String: Any]] else {
            return []
        }
        return records
    }
}

/// インポートエラー
public enum ImportError: LocalizedError {
    case fileNotFound
    case invalidFormat(String)
    case parseError(String)
    case emptyFile
    case unsupportedFormat

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
        }
    }
}

/// インポートサービス
public struct ImportService {

    // MARK: - File Open Dialog

    /// ファイル選択ダイアログを表示
    @MainActor
    public static func showOpenDialog() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Select a file to import"
        panel.allowedContentTypes = [.json, .commaSeparatedText, UTType(filenameExtension: "jsonl") ?? .plainText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - Parse Files

    /// ファイルを読み込んでパース
    public static func parseFile(at url: URL) throws -> ImportResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw ImportError.emptyFile
        }

        let ext = url.pathExtension.lowercased()

        switch ext {
        case "json":
            return try parseJSON(data: data, sourceURL: url)
        case "jsonl":
            return try parseJSONL(data: data, sourceURL: url)
        case "csv":
            return try parseCSV(data: data, sourceURL: url)
        default:
            throw ImportError.unsupportedFormat
        }
    }

    /// JSON配列をパース
    private static func parseJSON(data: Data, sourceURL: URL) throws -> ImportResult {
        let json = try JSONSerialization.jsonObject(with: data, options: [])

        if let array = json as? [[String: Any]] {
            guard !array.isEmpty else {
                throw ImportError.emptyFile
            }
            return try ImportResult(records: array, format: .json, sourceURL: sourceURL)
        } else if let single = json as? [String: Any] {
            return try ImportResult(records: [single], format: .json, sourceURL: sourceURL)
        } else {
            throw ImportError.invalidFormat("JSON must be an array of objects or a single object")
        }
    }

    /// JSONLをパース（1行1JSON）
    private static func parseJSONL(data: Data, sourceURL: URL) throws -> ImportResult {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidFormat("Invalid UTF-8 encoding")
        }

        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else {
            throw ImportError.emptyFile
        }

        var records: [[String: Any]] = []

        for (index, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData, options: []),
                  let record = json as? [String: Any] else {
                throw ImportError.parseError("Line \(index + 1) is not a valid JSON object")
            }
            records.append(record)
        }

        return try ImportResult(records: records, format: .jsonl, sourceURL: sourceURL)
    }

    /// CSVをパース
    private static func parseCSV(data: Data, sourceURL: URL) throws -> ImportResult {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidFormat("Invalid UTF-8 encoding")
        }

        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else {
            throw ImportError.invalidFormat("CSV must have a header row and at least one data row")
        }

        let headers = parseCSVLine(lines[0])
        var records: [[String: Any]] = []

        for line in lines.dropFirst() {
            let values = parseCSVLine(line)
            var record: [String: Any] = [:]

            for (index, header) in headers.enumerated() {
                if index < values.count {
                    let value = values[index]
                    record[header] = inferValue(value)
                }
            }

            if !record.isEmpty {
                records.append(record)
            }
        }

        guard !records.isEmpty else {
            throw ImportError.emptyFile
        }

        return try ImportResult(records: records, format: .csv, sourceURL: sourceURL)
    }

    // MARK: - CSV Helpers

    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }

        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    private static func inferValue(_ string: String) -> Any {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        // 空文字
        if trimmed.isEmpty {
            return NSNull()
        }

        // 真偽値
        if trimmed.lowercased() == "true" {
            return true
        }
        if trimmed.lowercased() == "false" {
            return false
        }

        // 整数
        if let intValue = Int(trimmed) {
            return intValue
        }

        // 浮動小数点数
        if let doubleValue = Double(trimmed) {
            return doubleValue
        }

        // 文字列
        return trimmed
    }
}
