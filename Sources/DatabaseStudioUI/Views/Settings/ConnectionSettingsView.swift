import SwiftUI

/// Connection settings view.
struct ConnectionSettingsView: View {
    @Bindable var viewModel: AppViewModel
    var isRequired: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var historyService = ConnectionHistoryService.shared
    @State private var refreshTrigger = false
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            Form {
                // Favorites
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

                // Recent
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

                // Connection
                Section("Connection") {
                    LabeledContent("Database File") {
                        HStack {
                            TextField("Path", text: $viewModel.filePath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                            Button("Browse...") {
                                browseForDatabaseFile()
                            }
                        }
                    }

                    // Show Root Path only for FoundationDB
                    if BackendType.detect(from: viewModel.filePath) == .foundationDB {
                        LabeledContent("Root Path") {
                            TextField("e.g. app/production", text: $viewModel.rootDirectoryPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        Text("Empty shows all from root")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Detected backend indicator
                    HStack {
                        let detected = BackendType.detect(from: viewModel.filePath)
                        Image(systemName: detected == .sqlite ? "cylinder" : "server.rack")
                            .foregroundStyle(.secondary)
                        Text(detected == .sqlite ? "SQLite" : "FoundationDB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Error display
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
                if !isRequired {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
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
                        .disabled(viewModel.filePath.isEmpty)
                    }
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 550, minHeight: 350, idealHeight: 450)
        .id(refreshTrigger)
    }

    private func browseForDatabaseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        panel.message = "Select database file (.cluster, .sqlite, or .db)"

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.filePath = url.path
        }
    }

    private func selectConnection(_ connection: ConnectionInfo) {
        viewModel.filePath = connection.filePath
        viewModel.rootDirectoryPath = connection.rootDirectoryPath
    }

    private func connectAndSaveHistory() async {
        await viewModel.connect()
        if case .connected = viewModel.connectionState {
            historyService.addOrUpdate(
                filePath: viewModel.filePath,
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

/// Connection row view.
private struct ConnectionRowView: View {
    let connection: ConnectionInfo
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            // Backend icon
            Image(systemName: connection.backendType == .sqlite ? "cylinder" : "server.rack")
                .foregroundStyle(.secondary)
                .frame(width: 16)

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
