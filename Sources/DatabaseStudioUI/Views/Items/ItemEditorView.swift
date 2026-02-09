import SwiftUI

/// Item編集モード
public enum ItemEditorMode: Equatable {
    case create
    case edit(DecodedItem)

    public static func == (lhs: ItemEditorMode, rhs: ItemEditorMode) -> Bool {
        switch (lhs, rhs) {
        case (.create, .create):
            return true
        case (.edit(let a), .edit(let b)):
            return a.id == b.id
        default:
            return false
        }
    }
}

/// Item編集ビュー
public struct ItemEditorView: View {
    let mode: ItemEditorMode
    let typeName: String
    let onSave: (String, [String: Any]) async throws -> Void
    let onCancel: () -> Void

    @State private var itemID: String
    @State private var jsonText: String
    @State private var validationError: String?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    public init(
        mode: ItemEditorMode,
        typeName: String,
        onSave: @escaping (String, [String: Any]) async throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.typeName = typeName
        self.onSave = onSave
        self.onCancel = onCancel

        switch mode {
        case .create:
            _itemID = State(initialValue: UUID().uuidString)
            _jsonText = State(initialValue: "{\n  \n}")
        case .edit(let item):
            _itemID = State(initialValue: item.id)
            _jsonText = State(initialValue: item.prettyJSON)
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ID入力（作成モードのみ編集可能）
                HStack {
                    Text("ID:")
                        .foregroundStyle(.secondary)

                    if mode == .create {
                        TextField("Item ID", text: $itemID)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text(itemID)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if mode == .create {
                        Button {
                            itemID = UUID().uuidString
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Generate new ID")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // JSONエディタ
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("JSON Data")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            formatJSON()
                        } label: {
                            Image(systemName: "text.alignleft")
                        }
                        .buttonStyle(.borderless)
                        .help("Format JSON")
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    TextEditor(text: $jsonText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .onChange(of: jsonText) { _, _ in
                            validateJSON()
                        }
                }

                // バリデーションエラー
                if let error = validationError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                }

                // 保存中インジケーター
                if isSaving {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Saving...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle(mode == .create ? "Create New Item" : "Edit Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button("Save") {
                            Task {
                                await saveItem()
                            }
                        }
                        .disabled(!isValid)
                    }
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 550, minHeight: 400, idealHeight: 500)
        .onAppear {
            validateJSON()
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !itemID.isEmpty && validationError == nil
    }

    private func validateJSON() {
        guard let data = jsonText.data(using: .utf8) else {
            validationError = "Invalid UTF-8 encoding"
            return
        }

        do {
            let _ = try JSONSerialization.jsonObject(with: data, options: [])
            validationError = nil
        } catch {
            validationError = "Invalid JSON: \(error.localizedDescription)"
        }
    }

    private func formatJSON() {
        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let formatted = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let formattedString = String(data: formatted, encoding: .utf8) else {
            return
        }
        jsonText = formattedString
    }

    // MARK: - Save

    private func saveItem() async {
        guard isValid else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            guard let data = jsonText.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                validationError = "JSON must be an object"
                return
            }

            try await onSave(itemID, json)
            dismiss()
        } catch {
            validationError = error.localizedDescription
        }
    }
}

// MARK: - Delete Confirmation

/// 削除確認ダイアログ
public struct DeleteConfirmationView: View {
    let itemCount: Int
    let onConfirm: () async -> Void
    let onCancel: () -> Void

    @State private var isDeleting = false
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                Text(itemCount == 1 ? "Delete Item?" : "Delete \(itemCount) Items?")
                    .font(.headline)

                Text("This action cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if isDeleting {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Confirm Delete")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete") {
                        Task {
                            isDeleting = true
                            await onConfirm()
                            isDeleting = false
                            dismiss()
                        }
                    }
                    .tint(.red)
                    .disabled(isDeleting)
                }
            }
        }
        .frame(minWidth: 300, minHeight: 200)
    }
}

// MARK: - Previews

#Preview("Create Mode") {
    ItemEditorView(
        mode: .create,
        typeName: "User",
        onSave: { id, json in
            print("Save: \(id), \(json)")
        },
        onCancel: {
            print("Cancel")
        }
    )
    .frame(width: 600, height: 500)
}

#Preview("Edit Mode") {
    ItemEditorView(
        mode: .edit(PreviewData.userItems[0]),
        typeName: "User",
        onSave: { id, json in
            print("Save: \(id), \(json)")
        },
        onCancel: {
            print("Cancel")
        }
    )
    .frame(width: 600, height: 500)
}

#Preview("Delete Confirmation") {
    DeleteConfirmationView(
        itemCount: 3,
        onConfirm: {
            print("Delete confirmed")
        },
        onCancel: {
            print("Cancel")
        }
    )
}
