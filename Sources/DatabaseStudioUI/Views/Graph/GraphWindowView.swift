import SwiftUI
import Core

/// グラフウィンドウの共有状態
@Observable @MainActor
public final class GraphWindowState {
    public static let shared = GraphWindowState()

    public var document: GraphDocument?
    public var entityName: String = ""
    public var isLoading: Bool = false
    public var loadFailureMessage: String?

    /// Loads the document after the graph window appears.
    public var loadDocument: (@MainActor () async throws -> GraphDocument?)?

    /// Reloads the document from its data source.
    public var refreshDocument: (@MainActor () async throws -> GraphDocument?)?

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
        } else if let loadFailureMessage = state.loadFailureMessage {
            ContentUnavailableView(
                "Unable to Load Graph",
                systemImage: "exclamationmark.triangle",
                description: Text(loadFailureMessage)
            )
        } else if state.isLoading {
            ProgressView("Loading graph data…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    guard let loadDocument = state.loadDocument else {
                        state.isLoading = false
                        return
                    }
                    do {
                        state.document = try await loadDocument()
                    } catch {
                        state.loadFailureMessage = error.localizedDescription
                    }
                    state.isLoading = false
                }
        } else {
            ContentUnavailableView(
                "No Graph Data",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("Open a graph from an entity with a Graph index")
            )
        }
    }
}

// MARK: - Event Graph Window

/// イベント詳細グラフウィンドウの共有状態
@Observable @MainActor
public final class EventGraphWindowState {
    public static let shared = EventGraphWindowState()

    public var document: GraphDocument?
    public var focusNodeID: String?
    public var entityName: String = ""

    public init() {}
}

/// 別ウィンドウでイベントノードにフォーカスしたグラフビュー
public struct EventGraphWindowView: View {
    let state = EventGraphWindowState.shared

    public init() {}

    public var body: some View {
        if let document = state.document {
            GraphView(document: document, focusNodeID: state.focusNodeID, focusHops: 1)
                .navigationTitle("\(state.entityName) – Event")
        } else {
            ContentUnavailableView(
                "No Event Data",
                systemImage: "calendar",
                description: Text("Open an event from the Events tab in the inspector")
            )
        }
    }
}
