import SwiftUI

/// Connection settings view.
struct ConnectionSettingsView: View {
    @Bindable var viewModel: AppViewModel
    var isRequired: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var historyService = ConnectionHistoryService.shared
    @State private var refreshTrigger = false
    @State private var isConnecting = false
    @State private var connectTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                connectingSection
                errorSection
                favoritesSection
                recentsSection
                connectionSection
            }
            .formStyle(.grouped)
            .navigationTitle("Connection")
            .toolbar(content: connectionToolbar)
        }
        .frame(minWidth: 500, idealWidth: 550, minHeight: 350, idealHeight: 450)
        .id(refreshTrigger)
    }

    @ViewBuilder
    private var connectingSection: some View {
        if isConnecting {
            Section("Status") {
                ConnectingStatusView(
                    filePath: viewModel.filePath,
                    onCancel: cancelConnectionAttempt
                )
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorPresentation = viewModel.connectionErrorPresentation {
            Section("Error") {
                ConnectionErrorDetailView(errorPresentation: errorPresentation)
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
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
    }

    @ViewBuilder
    private var recentsSection: some View {
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
    }

    private var detectedBackend: BackendType {
        BackendType.detect(from: viewModel.filePath)
    }

    private var connectionSection: some View {
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

            if detectedBackend == .foundationDB {
                LabeledContent("Root Path") {
                    TextField("e.g. app/production", text: $viewModel.rootDirectoryPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Text("Empty shows all from root")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Image(systemName: detectedBackend == .sqlite ? "cylinder" : "server.rack")
                    .foregroundStyle(.secondary)
                Text(detectedBackend == .sqlite ? "SQLite" : "FoundationDB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ToolbarContentBuilder
    private func connectionToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if isConnecting {
                Button("Cancel") {
                    cancelConnectionAttempt()
                }
            } else if !isRequired {
                Button("Cancel") {
                    dismiss()
                }
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Connect") {
                startConnectionAttempt()
            }
            .disabled(viewModel.filePath.isEmpty || isConnecting)
        }
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

    private func startConnectionAttempt() {
        connectTask?.cancel()
        isConnecting = true
        connectTask = Task {
            defer {
                Task { @MainActor in
                    isConnecting = false
                    connectTask = nil
                }
            }
            await connectAndSaveHistory()
        }
    }

    private func cancelConnectionAttempt() {
        connectTask?.cancel()
        connectTask = nil
        isConnecting = false
        viewModel.cancelConnectionAttempt()
    }

}

private struct ConnectingStatusView: View {
    let filePath: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connecting…")
                    .font(.headline)
                Text(filePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel", action: onCancel)
        }
        .padding(.vertical, 4)
    }
}

private struct ConnectionErrorDetailView: View {
    let errorPresentation: ConnectionErrorPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(errorPresentation.title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(errorPresentation.message)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            if let recoverySuggestion = errorPresentation.recoverySuggestion {
                Text(recoverySuggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
