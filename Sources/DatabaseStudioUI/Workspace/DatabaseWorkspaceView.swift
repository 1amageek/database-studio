import SwiftUI

/// Keeps server and file navigation inside the base database window.
public struct DatabaseWorkspaceView: View {
    @Binding private var destination: WorkspaceDestination?
    @State private var contentRevision: UInt64 = 0
    @State private var didRestore = false
    @State private var failure: String?

    public init(destination: Binding<WorkspaceDestination?>) { _destination = destination }

    public var body: some View {
        Group {
            switch destination {
            case .database(let connection): MainView(recentConnection: connection)
            case .server:
                RuntimeConnectionView(connectionID: Binding(
                    get: { if case .server(let id) = destination { return id }; return nil },
                    set: { destination = .server($0) }))
            case nil: ProgressView("Restoring Workspace…")
            }
        }
        .id(contentRevision)
        .focusedSceneValue(\.workspaceNavigation, WorkspaceNavigation(open: open))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu("Connections", systemImage: "externaldrive.connected.to.line.below") {
                    Button("Connect to Server…") { open(.server(nil)) }.contentShape(Rectangle())
                    Button("Open Database…") { open(.database(nil)) }.contentShape(Rectangle())
                    Menu("Open Recent") { RecentConnectionsMenu(openDestination: open) }
                }.contentShape(Rectangle()).accessibilityIdentifier("workspace.connections")
            }
        }
        .task {
            guard !didRestore else { return }
            didRestore = true
            guard destination == nil else { return }
            do {
                let databases = ConnectionHistoryStore.shared
                let servers = RuntimeConnectionHistory.shared
                try databases.load()
                try servers.load()
                destination = ConnectionRestoration.destination(local: databases.mostRecent, server: servers.connections.first)?.workspaceDestination ?? .server(nil)
            } catch {
                failure = error.localizedDescription
                destination = .server(nil)
            }
        }
        .alert("Unable to Restore Workspace", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }.contentShape(Rectangle())
        } message: { Text(failure ?? "") }
    }

    private func open(_ value: WorkspaceDestination) {
        contentRevision &+= 1
        destination = value
    }
}
