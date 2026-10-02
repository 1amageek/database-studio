import SwiftUI
import DatabaseKit

/// グラフウィンドウの共有状態
@Observable @MainActor
public final class GraphWindowState {
    public static let shared = GraphWindowState()

    public var document: GraphDocument?
    public var entityName: String = ""
    public var isLoading: Bool = false
    public var loadFailureMessage: String?

    /// Loads the document after the graph window appears.
    public private(set) var loadGeneration: UInt64 = 0
    public var loadDocument: (@MainActor () async throws -> GraphDocument?)? {
        didSet { loadGeneration &+= 1 }
    }

    /// Reloads the document from its data source.
    public var refreshDocument: (@MainActor () async throws -> GraphDocument?)?

    public func showExample() {
        let individuals = GraphSampleData.rdfDocument
        let ontology = GraphSampleData.ontologyDocument
        let classIDs = Set(ontology.nodes.map(\.id))
        document = GraphDocument(nodes: ontology.nodes + individuals.nodes.filter { !classIDs.contains($0.id) },
                                 edges: ontology.edges + individuals.edges)
        entityName = "Example · Automotive ontology"
        loadDocument = nil
        refreshDocument = nil
        isLoading = false
        loadFailureMessage = nil
    }

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
                .task(id: state.loadGeneration) {
                    let generation = state.loadGeneration
                    guard let loadDocument = state.loadDocument else {
                        state.isLoading = false
                        return
                    }
                    do {
                        let document = try await loadDocument()
                        guard !Task.isCancelled, generation == state.loadGeneration else { return }
                        state.document = document
                        if document == nil { state.loadFailureMessage = "The source returned no graph document." }
                    } catch {
                        guard !Task.isCancelled, generation == state.loadGeneration else { return }
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
