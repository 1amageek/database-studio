import SwiftUI

/// 別ウィンドウで表示する Vector Explorer
public struct VectorWindowView: View {
    let state = VectorWindowState.shared

    public init() {}

    public var body: some View {
        if let document = state.document {
            VectorView(document: document)
                .navigationTitle("\(state.entityName) – Vector Explorer")
        } else {
            ContentUnavailableView(
                "No Vector Data",
                systemImage: "cube.transparent",
                description: Text("Open vector explorer from an entity with vector embeddings")
            )
        }
    }
}
