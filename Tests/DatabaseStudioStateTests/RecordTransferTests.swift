import Foundation
import Testing
@testable import DatabaseStudioUI

@MainActor
@Suite("Record Import and Export Behavior")
struct RecordTransferTests {
    @Test("JSON Lines parsing reads slices without dropping blank lines or records")
    func jsonLinesParsing() async throws {
        let sourceURL = try writeTemporaryFile(
            extension: "jsonl",
            contents: "{\"id\":\"one\",\"value\":1}\r\n  \r\n{\"id\":\"two\",\"value\":2}"
        )
        defer { removeTemporaryFile(sourceURL) }

        let parsedImport = try await RecordImporter.parseRecords(at: sourceURL)

        #expect(parsedImport.format == .jsonLines)
        #expect(parsedImport.recordCount == 2)
        #expect(parsedImport.records[0]["id"] as? String == "one")
        #expect(parsedImport.records[1]["value"] as? Int == 2)
    }

    @Test("CSV parsing preserves quoted commas and escaped quotes")
    func csvQuotedFields() async throws {
        let sourceURL = try writeTemporaryFile(
            extension: "csv",
            contents: "name,note,count\r\n\"Alice, A.\",\"said \"\"hello\"\"\",42\r\n"
        )
        defer { removeTemporaryFile(sourceURL) }

        let parsedImport = try await RecordImporter.parseRecords(at: sourceURL)

        #expect(parsedImport.recordCount == 1)
        #expect(parsedImport.records[0]["name"] as? String == "Alice, A.")
        #expect(parsedImport.records[0]["note"] as? String == "said \"hello\"")
        #expect(parsedImport.records[0]["count"] as? Int == 42)
    }

    @Test("CSV parsing rejects rows whose field count differs from the header")
    func csvFieldCountMismatch() async throws {
        let sourceURL = try writeTemporaryFile(
            extension: "csv",
            contents: "name,count\nAlice,1,unexpected\n"
        )
        defer { removeTemporaryFile(sourceURL) }

        do {
            _ = try await RecordImporter.parseRecords(at: sourceURL)
            Issue.record("Expected a field-count validation failure")
        } catch let importError as RecordImportError {
            guard case .invalidFormat(let message) = importError else {
                Issue.record("Expected RecordImportError.invalidFormat, received \(importError)")
                return
            }
            #expect(message.contains("expected 2"))
        } catch {
            Issue.record("Expected RecordImportError.invalidFormat, received \(error)")
        }
    }

    @Test("JSON Lines export reports an invalid record instead of omitting it")
    func jsonLinesExportFailure() {
        let invalidRecord = StudioRecord(
            id: "invalid",
            typeName: "Event",
            fields: ["date": Date()],
            jsonByteCount: 0
        )

        do {
            _ = try RecordExporter.encodeJSONLines([invalidRecord])
            Issue.record("Expected RecordExportError.recordSerializationFailed")
        } catch RecordExportError.recordSerializationFailed(let identifier, let format, _) {
            #expect(identifier == "invalid")
            #expect(format == .jsonLines)
        } catch {
            Issue.record("Expected RecordExportError.recordSerializationFailed, received \(error)")
        }
    }

    @Test("Record formatting reports invalid JSON values")
    func recordFormattingFailure() {
        let invalidRecord = StudioRecord(
            id: "invalid",
            typeName: "Event",
            fields: ["date": Date()],
            jsonByteCount: 0
        )

        do {
            _ = try invalidRecord.formattedJSON()
            Issue.record("Expected StudioRecordFormattingError.jsonEncodingFailed")
        } catch StudioRecordFormattingError.jsonEncodingFailed(let identifier, _) {
            #expect(identifier == "invalid")
        } catch {
            Issue.record("Expected StudioRecordFormattingError.jsonEncodingFailed, received \(error)")
        }
    }

    private func writeTemporaryFile(extension fileExtension: String, contents: String) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("database-studio-record-transfer-\(UUID())")
            .appendingPathExtension(fileExtension)
        try contents.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    private func removeTemporaryFile(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Could not remove temporary test file at \(url.path): \(error)")
        }
    }
}
