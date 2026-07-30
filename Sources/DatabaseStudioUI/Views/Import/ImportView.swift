import SwiftUI

/// Presents record import selection, preview, and confirmation.
public struct ImportView: View {
    let typeName: String
    let onImport: @MainActor ([[String: Any]]) async throws -> Int
    let onCancel: () -> Void

    @State private var parsedImport: ParsedRecordImport?
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importedCount: Int?
    @State private var idField: String = "_id"
    @State private var previewRecords: [[String: Any]] = []

    @Environment(\.dismiss) private var dismiss

    public init(
        typeName: String,
        onImport: @escaping @MainActor ([[String: Any]]) async throws -> Int,
        onCancel: @escaping () -> Void
    ) {
        self.typeName = typeName
        self.onImport = onImport
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let parsedImport {
                    importPreview(parsedImport)
                } else if isLoading {
                    ProgressView("Reading file...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    fileSelectionView
                }

                // Import outcome.
                if let error = errorMessage {
                    HStack {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                }

                if let count = importedCount {
                    HStack {
                        Label("\(count) items imported successfully", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                }
            }
            .navigationTitle("Import to \(typeName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                if parsedImport != nil {
                    ToolbarItem(placement: .automatic) {
                        Button("Select Another File") {
                            parsedImport = nil
                            previewRecords = []
                            errorMessage = nil
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button("Import") {
                            Task {
                                await performImport()
                            }
                        }
                        .disabled(parsedImport == nil)
                    }
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 650, minHeight: 500, idealHeight: 550)
    }

    // MARK: - File Selection

    private var fileSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Select a file to import")
                .font(.title3)

            Text("Supported formats: JSON, JSONL, CSV")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Choose File...") {
                selectFile()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Import Preview

    private func importPreview(_ parsedImport: ParsedRecordImport) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(parsedImport.recordCount) records", systemImage: "doc.text")
                Divider().frame(height: 16)
                Label(parsedImport.format.rawValue, systemImage: "doc")
                Divider().frame(height: 16)
                Label(parsedImport.sourceURL.lastPathComponent, systemImage: "folder")

                Spacer()

                HStack(spacing: 4) {
                    Text("ID field:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $idField) {
                        Text("_id").tag("_id")
                        Text("id").tag("id")
                        Text("Auto").tag("__auto__")
                        ForEach(detectedFields, id: \.self) { field in
                            if field != "_id" && field != "id" {
                                Text(field).tag(field)
                            }
                        }
                    }
                    .frame(width: 120)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            List {
                ForEach(Array(previewRecords.prefix(20).enumerated()), id: \.offset) { index, record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("#\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            if let identifier = extractID(from: record) {
                                Text(identifier)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }

                        Text(formatPreview(record))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }

                if parsedImport.recordCount > 20 {
                    Text("... and \(parsedImport.recordCount - 20) more records")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Actions

    @MainActor
    private func selectFile() {
        let sourceURL: URL
        do {
            guard let selectedURL = try RecordImporter.selectImportSource() else { return }
            sourceURL = selectedURL
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let parsedImport = try await RecordImporter.parseRecords(at: sourceURL)
                let records = parsedImport.records
                self.parsedImport = parsedImport
                self.previewRecords = records
                self.isLoading = false
                let fields = detectedFields
                if fields.contains("_id") {
                    idField = "_id"
                } else if fields.contains("id") {
                    idField = "id"
                } else {
                    idField = "__auto__"
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    @MainActor
    private func performImport() async {
        guard let parsedImport else { return }

        isImporting = true
        errorMessage = nil

        do {
            let selectedIdentifierField = idField
            var records = parsedImport.records
            for index in records.indices {
                records[index].removeValue(forKey: "_type")

                if selectedIdentifierField == "__auto__" {
                    records[index]["_id"] = UUID().uuidString
                } else if selectedIdentifierField != "_id" {
                    if let identifier = records[index][selectedIdentifierField] {
                        records[index]["_id"] = identifier
                    } else {
                        records[index]["_id"] = UUID().uuidString
                    }
                }
            }

            let importedRecordCount = try await onImport(records)
            importedCount = importedRecordCount
            isImporting = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
        }
    }

    // MARK: - Record Preview Formatting

    private var detectedFields: [String] {
        var fields = Set<String>()
        for record in previewRecords.prefix(10) {
            fields.formUnion(record.keys)
        }
        return fields.sorted()
    }

    private func extractID(from record: [String: Any]) -> String? {
        if idField == "__auto__" {
            return "(auto)"
        }
        if let identifier = record[idField] {
            return "\(identifier)"
        }
        return nil
    }

    private func formatPreview(_ record: [String: Any]) -> String {
        let filtered = record.filter { $0.key != "_id" && $0.key != "_type" && $0.key != idField }
        let preview = filtered.prefix(4).map { "\($0.key): \(formatValue($0.value))" }.joined(separator: ", ")
        return "{ \(preview)\(filtered.count > 4 ? ", ..." : "") }"
    }

    private func formatValue(_ value: Any) -> String {
        if let string = value as? String {
            return "\"\(string.prefix(20))\(string.count > 20 ? "..." : "")\""
        } else if let number = value as? NSNumber {
            return "\(number)"
        } else if value is NSNull {
            return "null"
        } else {
            return "..."
        }
    }
}

#Preview {
    ImportView(
        typeName: "User",
        onImport: { records in
            print("Importing \(records.count) records")
            return records.count
        },
        onCancel: {
            print("Cancel")
        }
    )
}
