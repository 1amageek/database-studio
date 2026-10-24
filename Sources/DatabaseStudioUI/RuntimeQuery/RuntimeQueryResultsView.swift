import SwiftUI
import Foundation
import DatabaseKit
import DatabaseWire

/// Data and Query compose the same canonical outcome presentation.
struct RuntimeQueryResultsView: View {
    let query: RuntimeQuery
    var sourceContent: AnyView?

    var body: some View {
        VStack(spacing: 0) {
            if let response = query.response {
                if response.results.count > 1 {
                    HStack {
                        Picker("Statement", selection: Binding(get: { query.selectedResultIndex },
                            set: { query.selectResult($0) })) {
                            ForEach(response.results.indices, id: \.self) { index in
                                Text("\(index + 1) · \(title(response.results[index]))").tag(index)
                            }
                        }.pickerStyle(.menu).contentShape(Rectangle()).disabled(query.isRunning)
                        Spacer()
                    }.padding(8)
                }
                if let count = query.selectedResult?.affectedRows {
                    Text("\(count) rows affected").font(.caption).foregroundStyle(.secondary).padding(4)
                }
            }
            outcome
        }.id(query.pageRevision)
    }

    @ViewBuilder private var outcome: some View {
        switch query.selectedResult {
        case .rows, .rdfGraph:
            if let presentation = query.presentation {
                ResultPageView(state: presentation, sourceContent: sourceContent)
            }
        case .boolean(let value):
            ResultSourcePane(sourceContent: sourceContent) {
                Text(value.value ? "true" : "false").font(.system(.title, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .command(let kind, _):
            ResultSourcePane(sourceContent: sourceContent) {
                Text(String(describing: kind)).font(.system(.title, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .copy(let bytes, _):
            ResultSourcePane(sourceContent: sourceContent) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("COPY · \(bytes.count) bytes").font(.headline)
                    // The display boundary creates only a bounded hexadecimal preview.
                    Text(bytes.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " "))
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    if bytes.count > 64 { Text("First 64 bytes, shown in hexadecimal").foregroundStyle(.secondary) }
                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        case .block:
            Text("A nested result block is invalid.").foregroundStyle(.red)
        case nil:
            ResultSourcePane(sourceContent: sourceContent) {
                ContentUnavailableView("Run a Query", systemImage: "terminal", description: Text("Results come from the connected server."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func title(_ result: QueryExecuteOperation.Response) -> String {
        switch result {
        case .rows: "Rows"
        case .boolean: "Boolean"
        case .rdfGraph: "RDF graph"
        case .command(let kind, _): String(describing: kind)
        case .copy: "COPY"
        case .block: "Block"
        }
    }
}
