import SwiftUI

/// Analysis is a projection of the current page, alongside Table and Raw.
struct RecordAnalysisView: View {
    let source: RecordAnalysisSource
    let onOpenRow: (Int) -> Void
    @State private var dataset: AnalysisDataset?
    @State private var failure: String?

    var body: some View {
        Group {
            if let dataset {
                AnalysisWorkspaceView(dataset: dataset, onOpenRow: onOpenRow)
            } else if let failure {
                ContentUnavailableView("Analysis Unavailable", systemImage: "chart.xyaxis.line", description: Text(failure))
            } else {
                ProgressView("Preparing page measurements…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            do { let result = try await source.dataset(); try Task.checkCancellation(); dataset = result }
            catch is CancellationError {}
            catch { failure = error.localizedDescription }
        }
    }
}
