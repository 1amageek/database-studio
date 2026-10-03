import SwiftUI
import DatabaseWire

/// Data and Query compose the same canonical result-page presentation.
struct RuntimeQueryResultsView: View {
    let query: RuntimeQuery
    var sourceContent: AnyView = AnyView(EmptyView())

    var body: some View {
        Group {
            switch query.response {
            case .rows(let page):
                ResultPageView(columns: page.columns, rows: query.rows, hasNextPage: page.continuation != nil, sourceContent: sourceContent)
            case .rdfGraph(let page):
                ResultPageView(quads: query.quads, hasNextPage: page.continuation != nil, sourceContent: sourceContent)
            case .boolean(let value):
                VStack(spacing: 0) {
                    Text(value ? "true" : "false").font(.system(.title, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    sourceContent
                }
            case nil:
                VStack(spacing: 0) {
                    ContentUnavailableView("Run a Query", systemImage: "terminal", description: Text("Results come from the connected server."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    sourceContent
                }
            }
        }.id(query.pageRevision)
    }
}
