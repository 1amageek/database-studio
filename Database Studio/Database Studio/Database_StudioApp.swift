import SwiftUI
import DatabaseStudioUI

@main
struct Database_StudioApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)

        Window("Graph Viewer", id: "graph-viewer") {
            GraphWindowView()
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
