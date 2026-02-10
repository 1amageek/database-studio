import SwiftUI

/// 別ウィンドウで表示する Search Console
public struct SearchWindowView: View {
    let state = SearchWindowState.shared

    public init() {}

    public var body: some View {
        if let document = state.document {
            SearchView(document: document)
                .navigationTitle("\(state.entityName) – Search")
        } else {
            ContentUnavailableView(
                "No Search Data",
                systemImage: "magnifyingglass",
                description: Text("Open search from an entity with text fields")
            )
        }
    }
}
