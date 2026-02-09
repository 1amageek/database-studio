import SwiftUI

/// 接続設定ビュー
struct ConnectionSettingsView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var historyService = ConnectionHistoryService.shared
    @State private var refreshTrigger = false
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            Form {
                // お気に入り
                if !historyService.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(historyService.favorites) { connection in
                            ConnectionRowView(
                                connection: connection,
                                onSelect: { selectConnection(connection) },
                                onToggleFavorite: { toggleFavorite(connection) },
                                onDelete: { deleteConnection(connection) }
                            )
                        }
                    }
                }

                // 最近使用
                if !historyService.recents.isEmpty {
                    Section("Recent") {
                        ForEach(historyService.recents.prefix(5)) { connection in
                            ConnectionRowView(
                                connection: connection,
                                onSelect: { selectConnection(connection) },
                                onToggleFavorite: { toggleFavorite(connection) },
                                onDelete: { deleteConnection(connection) }
                            )
                        }
                    }
                }

                // 新規接続
                Section("Connection") {
                    LabeledContent("Cluster File") {
                        HStack {
                            TextField("Path", text: $viewModel.clusterFilePath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                            Button("Browse...") {
                                browseForClusterFile()
                            }
                        }
                    }

                    LabeledContent("Root Path") {
                        TextField("例: app/production", text: $viewModel.rootDirectoryPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    Text("空の場合はルートから表示します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // エラー表示
                if case .error(let message) = viewModel.connectionState {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Connection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isConnecting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button("Connect") {
                            Task {
                                isConnecting = true
                                defer { isConnecting = false }
                                await connectAndSaveHistory()
                            }
                        }
                        .disabled(viewModel.clusterFilePath.isEmpty)
                    }
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 550, minHeight: 350, idealHeight: 450)
        .id(refreshTrigger)
    }

    private func browseForClusterFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        panel.directoryURL = URL(fileURLWithPath: "/etc/foundationdb")
        panel.message = "Select FDB cluster file"

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.clusterFilePath = url.path
        }
    }

    private func selectConnection(_ connection: ConnectionInfo) {
        viewModel.clusterFilePath = connection.clusterFilePath
        viewModel.rootDirectoryPath = connection.rootDirectoryPath
    }

    private func connectAndSaveHistory() async {
        await viewModel.connect()
        if case .connected = viewModel.connectionState {
            historyService.addOrUpdate(
                clusterFilePath: viewModel.clusterFilePath,
                rootDirectoryPath: viewModel.rootDirectoryPath
            )
            dismiss()
        }
    }

    private func toggleFavorite(_ connection: ConnectionInfo) {
        historyService.toggleFavorite(connection)
        refreshTrigger.toggle()
    }

    private func deleteConnection(_ connection: ConnectionInfo) {
        historyService.remove(connection)
        refreshTrigger.toggle()
    }
}

/// 接続行ビュー
private struct ConnectionRowView: View {
    let connection: ConnectionInfo
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.headline)

                Text(connection.displayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: connection.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(connection.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(connection.isFavorite ? "Remove from favorites" : "Add to favorites")

            Button {
                onSelect()
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .help("Use this connection")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onSelect()
        }
    }
}

// MARK: - Previews

#Preview("Connection Settings") {
    @Previewable @State var viewModel = AppViewModel()
    ConnectionSettingsView(viewModel: viewModel)
}

#Preview("Connection Settings - Error") {
    @Previewable @State var viewModel = AppViewModel.preview(connectionState: .error("Connection refused"))
    ConnectionSettingsView(viewModel: viewModel)
}
