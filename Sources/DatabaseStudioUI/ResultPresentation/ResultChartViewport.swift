import SwiftUI

struct ResultChartViewport: View {
    @Bindable var state: ResultPageState

    var body: some View {
        Group {
            if let data = state.currentChartData {
                AnalysisChartView(data: data, kind: state.chartKind, featureID: state.chartFeatureID,
                                  selectedRows: state.selectedIDs, selectedCluster: state.analysis?.clusterSession.selectedCluster,
                                  onSelectRow: state.selectChartRow, onSelectCluster: state.selectAnalysisCluster)
            } else if let failure = state.chartFailure ?? state.analysis?.clusterSession.failure {
                ContentUnavailableView("Chart Unavailable", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else if state.analysis?.clusterSession.configuration.mode == .numeric,
                      state.analysis?.clusterSession.configuration.numericFeatures.isEmpty == true {
                ContentUnavailableView("Configure Your Analysis", systemImage: "chart.xyaxis.line", description: Text("Choose measurements in Configure Analysis, then run the analysis."))
            } else if state.analysis?.clusterSession.isLoading == true || state.isPreparingCharts {
                ProgressView("Preparing analysis charts…")
            } else {
                ContentUnavailableView("Analysis Cancelled", systemImage: "chart.xyaxis.line", description: Text("Use Configure Analysis to run the analysis again."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: state.analysis?.clusterSession.revision) { await state.prepareCharts() }
    }
}
