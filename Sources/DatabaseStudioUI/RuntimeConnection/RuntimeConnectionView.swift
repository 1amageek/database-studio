import SwiftUI
import DatabaseClientHTTP

/// Authenticated server access within the base database workspace.
public struct RuntimeConnectionView: View {
    @Binding private var connectionID: UUID?
    @State private var connection = RuntimeConnection()
    @State private var endpoint = ""
    @State private var databaseID = "main"
    @State private var tenantID = ""
    @State private var workspaceID = ""
    @State private var accessToken = ""
    @State private var failure: String?
    @State private var operation: Task<Void, Never>?
    @State private var history = RuntimeConnectionHistory.shared
    @State private var rememberToken = false
    private let credentials = RuntimeCredentialStore()
    @State private var selectedEntity: String?
    @State private var showsQuery = false
    @State private var showsDatabaseInfo = false

    public init(connectionID: Binding<UUID?> = .constant(nil)) { _connectionID = connectionID }

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedEntity) {
                    Section("Entities") {
                        ForEach(connection.schema?.entities ?? [], id: \.name) { entity in
                            DisclosureGroup {
                                Section("Fields") {
                                    ForEach(entity.fields, id: \.number) { field in
                                        LabeledContent(field.name, value: String(describing: field.type))
                                            .font(.caption).help(field.nullable ? "Nullable" : "Required")
                                    }
                                }
                                Section("Indexes") {
                                    ForEach(entity.indexes, id: \.name) { index in
                                        Label(index.name, systemImage: "list.bullet.indent").font(.caption)
                                    }
                                }
                            } label: {
                                HStack {
                                    Label(entity.name, systemImage: "cube.box.fill")
                                    Spacer()
                                    Text("\(entity.fields.count) fields").font(.caption).foregroundStyle(.secondary)
                                }
                            }.tag(entity.name)
                        }
                    }
                }.listStyle(.sidebar).navigationTitle("Browser")
                    .accessibilityIdentifier("workspace.browser")
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label(connection.isConnected ? databaseID : "Not Connected", systemImage: connection.isConnected ? "circle.fill" : "circle")
                        .foregroundStyle(connection.isConnected ? Color.green : Color.secondary)
                    if !endpoint.isEmpty { Text(endpoint).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            if connection.isConnected {
                Group {
                    if showsQuery {
                        RuntimeQueryView(connection: connection, historyScope: [endpoint, databaseID, tenantID, workspaceID])
                    } else if let selectedEntity {
                        RuntimeRecordsView(connection: connection, entityName: selectedEntity).id(selectedEntity)
                    } else {
                        ContentUnavailableView("Select an Entity", systemImage: "tablecells", description: Text("Select a database entity in the browser, or open Query."))
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Picker("Source", selection: $showsQuery) {
                            Text("Data").tag(false)
                            Text("Query").tag(true)
                        }.pickerStyle(.segmented).frame(width: 130).contentShape(Rectangle())
                            .accessibilityIdentifier("workspace.source")
                    }
                }
            } else {
                connectionForm
            }
        }
        .navigationTitle(connection.isConnected ? databaseID : "Database Studio")
        .navigationSubtitle(connection.isConnected ? ([selectedEntity, tenantID.isEmpty ? nil : tenantID, workspaceID.isEmpty ? nil : workspaceID].compactMap { $0 }.joined(separator: " / ")) : "Connect to Server")
        .toolbar {
            if connection.isConnected {
                Button("Database Info", systemImage: "info.circle") { showsDatabaseInfo = true }
                    .contentShape(Rectangle()).accessibilityIdentifier("workspace.databaseInfo")
                    .popover(isPresented: $showsDatabaseInfo) { catalog.frame(width: 460, height: 560) }
                Button("Disconnect", systemImage: "network.slash") { disconnect() }
            }
        }
        .task {
            do {
                try history.load()
                if let connectionID {
                    guard let entry = history.connections.first(where: { $0.id == connectionID }) else {
                        failure = "This saved server connection is no longer available."
                        return
                    }
                    select(entry)
                }
            } catch { failure = error.localizedDescription }
        }
        .onChange(of: selectedEntity) { _, _ in showsQuery = false }
        .onDisappear { disconnect() }
    }

    private var connectionForm: some View {
        Form {
            if !history.connections.isEmpty {
                Section("Recent Servers") {
                    ForEach(history.connections) { entry in
                        HStack {
                            Button { select(entry) } label: {
                                VStack(alignment: .leading) {
                                    Text(entry.databaseID)
                                    Text(entry.endpoint.absoluteString).font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain).contentShape(Rectangle())
                            Spacer()
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                do {
                                    try credentials.remove(entry.id)
                                    try history.remove(entry.id)
                                } catch { failure = error.localizedDescription }
                            }.labelStyle(.iconOnly)
                        }
                    }
                }.disabled(connection.isConnecting)
            }
            Section("Database Server") {
                TextField("Endpoint URL", text: $endpoint)
                    .accessibilityIdentifier("runtime.endpoint")
                TextField("Database", text: $databaseID)
                TextField("Tenant (optional)", text: $tenantID)
                TextField("Workspace (optional)", text: $workspaceID)
                SecureField("Access token", text: $accessToken)
                    .accessibilityIdentifier("runtime.token")
                Toggle("Remember token in Keychain", isOn: $rememberToken)
            }.disabled(connection.isConnecting)
            if let failure {
                Section("Connection failed") { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            }
            HStack {
                if connection.isConnecting {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { disconnect() }
                } else {
                    Button("Connect") { connect() }
                        .buttonStyle(.borderedProminent)
                        .disabled(endpoint.isEmpty || accessToken.isEmpty || databaseID.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var catalog: some View {
        Form {
            if let failure {
                Section("Connection notice") { Text(failure).foregroundStyle(.red) }
            }
            Section("Server") {
                LabeledContent("Endpoint", value: endpoint)
                LabeledContent("Database", value: databaseID)
                if !tenantID.isEmpty { LabeledContent("Tenant", value: tenantID) }
                if !workspaceID.isEmpty { LabeledContent("Workspace", value: workspaceID) }
                LabeledContent("Runtime", value: connection.capabilities?.runtimeVersion ?? "")
            }
            if let entity = connection.schema?.entities.first(where: { $0.name == selectedEntity }) {
                Section(entity.name) {
                    ForEach(entity.fields, id: \.number) { field in
                        LabeledContent(field.name, value: String(describing: field.type) + (field.nullable ? " · nullable" : ""))
                    }
                }
            }
            Section("Advertised Features") {
                ForEach(connection.capabilities?.features ?? [], id: \.identifier) { feature in
                    LabeledContent(feature.identifier, value: String(feature.version))
                }
                Text("Operations remain subject to server authorization.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func connect() {
        operation?.cancel()
        failure = nil
        guard let url = URL(string: endpoint), url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil, url.query == nil else {
            failure = "Enter an HTTP or HTTPS endpoint without embedded credentials, a query, or a fragment."
            return
        }
        do {
            let configuration = try HTTPDatabaseConfiguration(endpoint: url, accessToken: accessToken, databaseID: databaseID,
                                                              tenantID: tenantID.isEmpty ? nil : tenantID,
                                                              workspaceID: workspaceID.isEmpty ? nil : workspaceID)
            operation = Task {
                do {
                    try await connection.connect(configuration: configuration)
                    defer { accessToken = "" }
                    try Task.checkCancellation()
                    let entry = try history.record(endpoint: configuration.endpoint, databaseID: configuration.databaseID,
                                                   tenantID: configuration.tenantID, workspaceID: configuration.workspaceID)
                    connectionID = entry.id
                    if rememberToken { try credentials.save(configuration.accessToken, for: entry.id) }
                    else { try credentials.remove(entry.id) }
                    accessToken = ""
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    failure = String(describing: error).replacingOccurrences(of: configuration.accessToken, with: "[redacted]")
                }
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    private func select(_ entry: SavedRuntimeConnection) {
        endpoint = entry.endpoint.absoluteString
        databaseID = entry.databaseID
        tenantID = entry.tenantID ?? ""
        workspaceID = entry.workspaceID ?? ""
        failure = nil
        accessToken = ""
        rememberToken = false
        do {
            if let token = try credentials.token(for: entry.id) {
                accessToken = token
                rememberToken = true
                connect()
            }
        } catch { failure = error.localizedDescription }
    }

    private func disconnect() {
        operation?.cancel()
        operation = nil
        selectedEntity = nil
        accessToken = ""
        Task { await connection.disconnect() }
    }
}
