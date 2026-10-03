import SwiftUI

struct AnalysisWorkspaceView: View {
    let dataset: AnalysisDataset
    let onOpenRow: (Int) -> Void
    @State private var showSource = false
    @State private var selectedNodeID: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Analysis · Current Result Page").font(.headline)
                    Text("\(dataset.document.nodes.count) rows · \(dataset.numericColumns.count) numeric fields")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let selectedNodeID, let index = RecordAnalysisSource.rowIndex(selectedNodeID) {
                    Button("Open Row \(index + 1)", systemImage: "doc.text.magnifyingglass") { onOpenRow(index) }
                        .contentShape(Rectangle()).accessibilityIdentifier("analysis.openRow")
                }
                Button("Source Details", systemImage: "info.circle") { showSource = true }.contentShape(Rectangle())
                    .popover(isPresented: $showSource) { sourceDetails }
            }.padding(.horizontal, 18).padding(.vertical, 12)
            Divider()
            GraphView(document: dataset.document, showsAllNodes: true, numericAnalysis: true,
                      allowsSourceRefresh: false, showsSidebar: false, onSelectNode: { selectedNodeID = $0 })
        }.frame(minHeight: 450)
    }

    private var sourceDetails: some View {
        ScrollView {
            Group {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Source & Coverage").font(.headline)
                    Text("\(dataset.document.nodes.count) retained rows from the current result page.").font(.callout)
                    ForEach(dataset.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    Divider()
                    Text("Missing Measurements").font(.callout.weight(.medium))
                    ForEach(dataset.numericColumns, id: \.self) { key in
                        HStack { Text(key); Spacer(); Text("\(dataset.missingCounts[key, default: 0]) missing").foregroundStyle(.secondary) }.font(.caption)
                    }
                    Divider()
                    ForEach(Array(dataset.provenance.enumerated()), id: \.offset) { _, text in Text(text).font(.caption).textSelection(.enabled) }
                }.padding(18)
            }
        }.frame(width: 500, height: 450)
    }

}
