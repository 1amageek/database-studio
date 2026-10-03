import SwiftUI
import DatabaseStudioUI

@main
struct DatabaseStudioApp: App {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.workspaceNavigation) private var workspaceNavigation

    private func open(_ destination: WorkspaceDestination) {
        if let workspaceNavigation { workspaceNavigation.open(destination) }
        else { openWindow(id: "database-workspace", value: destination) }
    }

    var body: some Scene {
        WindowGroup(id: "database-workspace", for: WorkspaceDestination.self) { $destination in
            DatabaseWorkspaceView(destination: $destination)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Menu("Open Recent") { RecentConnectionsMenu(openDestination: workspaceNavigation?.open) }
                Button("Connect to Server…") {
                    open(.server(nil))
                }
                .keyboardShortcut("k", modifiers: .command)
                Button("Open Database…") { open(.database(nil)) }
                Button("Open Example Graph") {
                    GraphWindowState.shared.showExample()
                    openWindow(id: "graph-viewer")
                }
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)

        Window("Graph Viewer", id: "graph-viewer") {
            GraphWindowView()
        }
        .defaultSize(width: 1100, height: 700)

        Window("Event Graph", id: "event-graph") {
            EventGraphWindowView()
        }
        .defaultSize(width: 1100, height: 700)

        Window("Map View", id: "map-view") {
            MapWindowView()
        }
        .defaultSize(width: 1100, height: 700)

        Window("Analytics", id: "analytics-dashboard") {
            AnalyticsWindowView()
        }
        .defaultSize(width: 1200, height: 800)

        Window("Search Console", id: "search-console") {
            SearchWindowView()
        }
        .defaultSize(width: 1100, height: 700)

        Window("Vector Explorer", id: "vector-explorer") {
            VectorWindowView()
        }
        .defaultSize(width: 1200, height: 800)

        Window("Version History", id: "version-history") {
            VersionWindowView()
        }
        .defaultSize(width: 1000, height: 700)
    }
}
