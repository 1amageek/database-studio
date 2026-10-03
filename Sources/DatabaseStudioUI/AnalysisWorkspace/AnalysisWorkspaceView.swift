import SwiftUI

struct AnalysisWorkspaceView: View {
    let dataset: AnalysisDataset
    let onOpenRow: (Int) -> Void
    @State private var showSource = false
    @State private var selectedNodeID: String?

    var body: some View {
        GraphView(document: dataset.document, showsAllNodes: true, numericAnalysis: true,
                  allowsSourceRefresh: false, showsSidebar: false, onSelectNode: { selectedNodeID = $0 })
            .frame(minHeight: 450)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if let selectedNodeID, let index = RecordAnalysisSource.rowIndex(selectedNodeID) {
                        Button("Open Row \(index + 1)", systemImage: "doc.text.magnifyingglass") { onOpenRow(index) }
                            .contentShape(Rectangle()).accessibilityIdentifier("analysis.openRow")
                    }
                    Button("Source Details", systemImage: "info.circle") { showSource = true }
                        .contentShape(Rectangle())
                        .help("Coverage and measurements in the current result page")
                        .popover(isPresented: $showSource) { sourceDetails }
                }
            }
    }

    private var sourceDetails: some View {
        Form {
            Section("Current Result Page") {
                LabeledContent("Retained rows", value: "\(dataset.document.nodes.count)")
                LabeledContent("Numeric fields", value: "\(dataset.numericColumns.count)")
                ForEach(Array(dataset.provenance.enumerated()), id: \.offset) { _, text in
                    Text(text).font(.caption).textSelection(.enabled)
                }
            }
            if !dataset.warnings.isEmpty {
                Section("Warnings") {
                    ForEach(dataset.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }
            }
            Section("Missing Measurements") {
                ForEach(dataset.numericColumns, id: \.self) { key in
                    LabeledContent(key, value: "\(dataset.missingCounts[key, default: 0]) missing")
                }
            }
        }.formStyle(.grouped).frame(width: 500, height: 450)
    }
}
