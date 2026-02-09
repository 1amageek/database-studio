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
    }
}
