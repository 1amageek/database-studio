import SwiftUI

/// Native recent-access commands shared by the File menu and main toolbar.
public struct RecentConnectionsMenu: View {
    @Environment(\.openWindow) private var openWindow
    @State private var servers = RuntimeConnectionHistory.shared
    @State private var databases = ConnectionHistoryStore.shared
    @State private var failure: String?
    private let openDestination: ((WorkspaceDestination) -> Void)?

    public init(openDestination: ((WorkspaceDestination) -> Void)? = nil) {
        self.openDestination = openDestination
    }

    public var body: some View {
        Group {
            if let failure { Text(failure) }
            if let failure = databases.failure { Text("Database history: " + failure) }
            Section("Servers") {
                ForEach(servers.connections) { entry in
                    Button {
                        open(.server(entry.id))
                    } label: {
                        Text(entry.databaseID + " — " + entry.endpoint.absoluteString + scope(entry))
                    }.contentShape(Rectangle())
                }
            }
            Section("Databases") {
                ForEach(databases.connections.sorted { $0.lastUsed > $1.lastUsed }) { entry in
                    Button {
                        open(.database(entry))
                    } label: {
                        Text(entry.name + " — " + entry.displayDescription)
                    }.contentShape(Rectangle())
                }
            }
            if servers.connections.isEmpty && databases.connections.isEmpty {
                Text("No Recent Connections")
            }
        }
        .task {
            do { try servers.load(); try databases.load(); failure = nil }
            catch { failure = "Unable to Read Connection History: " + error.localizedDescription }
        }
    }

    private func scope(_ entry: SavedRuntimeConnection) -> String {
        [entry.tenantID, entry.workspaceID].compactMap { $0 }.map { " / " + $0 }.joined()
    }

    private func open(_ destination: WorkspaceDestination) {
        if let openDestination { openDestination(destination) }
        else { openWindow(id: "database-workspace", value: destination) }
    }
}
