import SwiftUI

/// 別ウィンドウで表示する Analytics ダッシュボード
public struct AnalyticsWindowView: View {
    let state = AnalyticsWindowState.shared

    public init() {}

    public var body: some View {
        if let document = state.document {
            AnalyticsView(document: document)
                .navigationTitle("\(state.entityName) – Analytics")
        } else {
            ContentUnavailableView(
                "No Data",
                systemImage: "chart.bar",
                description: Text("Open analytics from an entity to visualize aggregations")
            )
        }
    }
}
