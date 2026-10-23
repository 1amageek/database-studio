import SwiftUI
import DatabaseWire

/// Data and Query compose the same canonical result-page presentation.
struct RuntimeQueryResultsView: View {
    let query: RuntimeQuery
    var sourceContent: AnyView?

    var body: some View {
        Group {
            switch query.response {
            case .rows, .rdfGraph:
                if let presentation = query.presentation {
                    ResultPageView(state: presentation, sourceContent: sourceContent)
                }
            case .boolean(let value):
                ResultSourcePane(sourceContent: sourceContent) {
                    Text(value ? "true" : "false").font(.system(.title, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case nil:
                ResultSourcePane(sourceContent: sourceContent) {
                    ContentUnavailableView("Run a Query", systemImage: "terminal", description: Text("Results come from the connected server."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.id(query.pageRevision)
    }
}
