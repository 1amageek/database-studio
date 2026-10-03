import SwiftUI
import DatabaseStudioUI

@main
struct DatabaseStudioApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "database-workspace", for: SavedDatabaseConnection.self) { $connection in
            MainView(recentConnection: connection)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Menu("Open Recent") { RecentConnectionsMenu() }
                Button("Connect to Server…") {
                    openWindow(id: "runtime-workspace")
                }
                Button("Open Example Graph") {
                    GraphWindowState.shared.showExample()
                    openWindow(id: "graph-viewer")
                }
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)

        WindowGroup("Database Server", id: "runtime-workspace", for: UUID.self) { $connectionID in
            RuntimeConnectionView(connectionID: $connectionID)
        }
        .defaultSize(width: 1100, height: 750)

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
