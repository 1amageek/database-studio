import SwiftUI

/// 別ウィンドウで表示する地図ビュー
public struct MapWindowView: View {
    let state = MapWindowState.shared

    public init() {}

    public var body: some View {
        if let document = state.document {
            MapContentView(document: document)
                .navigationTitle("\(state.entityName) – Map")
        } else {
            ContentUnavailableView(
                "No Map Data",
                systemImage: "map",
                description: Text("Open a map from an entity with spatial fields")
            )
        }
    }
}
