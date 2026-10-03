import SwiftUI

/// Renders contextual result content; the enclosing application keeps its sidebar.
struct ResultGraphViewport: View {
    @Bindable var graph: GraphViewState
    let onSelect: (String?) -> Void

    var body: some View {
        Group {
            if graph.isSpatial { GraphSpatialView(state: graph) }
            else if graph.usesFeatureClusters { GraphClusterView(state: graph) }
            else { GraphCanvas(state: graph) }
        }
        .clipped()
        .onChange(of: graph.selectedNodeID) { _, id in onSelect(id) }
        .onChange(of: graph.clusterSession.revision) { _, _ in graph.invalidateAnalysisVisibility() }
    }
}
