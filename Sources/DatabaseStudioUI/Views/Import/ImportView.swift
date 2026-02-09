import SwiftUI

/// インポートビュー
public struct ImportView: View {
    let typeName: String
    let onImport: ([[String: Any]]) async throws -> Int
    let onCancel: () -> Void

    @State private var importResult: ImportResult?
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importedCount: Int?
    @State private var idField: String = "_id"
    @State private var previewRecords: [[String: Any]] = []

    @Environment(\.dismiss) private var dismiss

    public init(
        typeName: String,
        onImport: @escaping ([[String: Any]]) async throws -> Int,
        onCancel: @escaping () -> Void
    ) {
        self.typeName = typeName
        self.onImport = onImport
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let result = importResult {
                    importPreview(result)
                } else if isLoading {
                    ProgressView("Reading file...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    fileSelectionView
                }

                // エラー/成功メッセージ
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

                if importResult != nil {
                    ToolbarItem(placement: .automatic) {
                        Button("Select Another File") {
                            importResult = nil
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
                        .disabled(importResult == nil)
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

    private func importPreview(_ result: ImportResult) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(result.count) records", systemImage: "doc.text")
                Divider().frame(height: 16)
                Label(result.format.rawValue, systemImage: "doc")
                Divider().frame(height: 16)
                Label(result.sourceURL.lastPathComponent, systemImage: "folder")

                Spacer()

                HStack(spacing: 4) {
                    Text("ID field:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $idField) {
                        Text("_id").tag("_id")
                        Text("id").tag("id")
                        Text("Auto").tag("__auto__")
                        ForEach(detectFields(result), id: \.self) { field in
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

                            if let id = extractID(from: record) {
                                Text(id)
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

                if result.count > 20 {
                    Text("... and \(result.count - 20) more records")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Actions

    private func selectFile() {
        guard let url = ImportService.showOpenDialog() else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result = try ImportService.parseFile(at: url)
                await MainActor.run {
                    self.importResult = result
                    self.previewRecords = result.getRecords()
                    self.isLoading = false
                    if detectFields(result).contains("_id") {
                        idField = "_id"
                    } else if detectFields(result).contains("id") {
                        idField = "id"
                    } else {
                        idField = "__auto__"
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func performImport() async {
        guard let result = importResult else { return }

        isImporting = true
        errorMessage = nil

        do {
            let currentIdField = idField
            var records = result.getRecords()
            records = records.map { record in
                var mutable = record
                mutable.removeValue(forKey: "_type")

                if currentIdField == "__auto__" {
                    mutable["_id"] = UUID().uuidString
                } else if currentIdField != "_id" {
                    if let idValue = mutable[currentIdField] {
                        mutable["_id"] = idValue
                    } else {
                        mutable["_id"] = UUID().uuidString
                    }
                }
                return mutable
            }

            let jsonData = try JSONSerialization.data(withJSONObject: records, options: [])
            guard let sendableRecords = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                throw ImportError.parseError("Failed to prepare records")
            }

            let count = try await onImport(sendableRecords)
            await MainActor.run {
                importedCount = count
                isImporting = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isImporting = false
            }
        }
    }

    // MARK: - Helpers

    private func detectFields(_ result: ImportResult) -> [String] {
        var fields = Set<String>()
        for record in result.getRecords().prefix(10) {
            fields.formUnion(record.keys)
        }
        return fields.sorted()
    }

    private func extractID(from record: [String: Any]) -> String? {
        if idField == "__auto__" {
            return "(auto)"
        }
        if let id = record[idField] {
            return "\(id)"
        }
        return nil
    }

    private func formatPreview(_ record: [String: Any]) -> String {
        let filtered = record.filter { $0.key != "_id" && $0.key != "_type" && $0.key != idField }
        let preview = filtered.prefix(4).map { "\($0.key): \(formatValue($0.value))" }.joined(separator: ", ")
        return "{ \(preview)\(filtered.count > 4 ? ", ..." : "") }"
    }

    private func formatValue(_ value: Any) -> String {
        if let str = value as? String {
            return "\"\(str.prefix(20))\(str.count > 20 ? "..." : "")\""
        } else if let num = value as? NSNumber {
            return "\(num)"
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
