import SwiftUI
import Core

/// グラフウィンドウの共有状態
@Observable @MainActor
public final class GraphWindowState {
    public static let shared = GraphWindowState()

    public var document: GraphDocument?
    public var entityName: String = ""

    /// データソースからドキュメントを再取得するクロージャ
    public var refreshAction: (@MainActor () async -> GraphDocument?)?

    public init() {}
}

/// 別ウィンドウで表示するグラフビュー
public struct GraphWindowView: View {
    let state = GraphWindowState.shared

    public init() {}

    public var body: some View {
        if let document = state.document {
            GraphView(document: document)
                .navigationTitle("\(state.entityName) – Graph")
        } else {
            ContentUnavailableView(
                "No Graph Data",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("Open a graph from an entity with a Graph index")
            )
        }
    }
}
