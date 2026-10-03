import SwiftUI
import DatabaseKit
import DatabaseWire

/// Composes result modes under the existing Data/Query navigation and sidebar.
struct ResultPageView: View {
    @State private var state: ResultPageState?
    private let failure: String?
    private let sourceContent: AnyView
    @State private var showInspector = false
    @State private var showRaw = false
    @State private var showCoverage = false

    init(columns: [QueryColumn], rows: [DatabaseWire.QueryRow], hasNextPage: Bool, sourceContent: AnyView = AnyView(EmptyView())) {
        self.sourceContent = sourceContent
        do {
            _state = State(initialValue: try ResultPageState(columns: columns, rows: rows, hasNextPage: hasNextPage))
            failure = nil
        } catch {
            _state = State(initialValue: nil)
            failure = error.localizedDescription
        }
    }

    init(quads: [RDFQuad], hasNextPage: Bool, sourceContent: AnyView = AnyView(EmptyView())) {
        self.sourceContent = sourceContent
        _state = State(initialValue: ResultPageState(quads: quads, hasNextPage: hasNextPage))
        failure = nil
    }

    var body: some View {
        if let state {
            @Bindable var state = state
            VStack(spacing: 0) {
                content(state).frame(maxWidth: .infinity, maxHeight: .infinity)
                sourceContent
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSubtitle(state.coverage)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Picker("Display", selection: $state.mode) {
                            ForEach(state.availableModes, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).contentShape(Rectangle())
                            .accessibilityIdentifier("result.mode")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if let graph = state.activeGraph {
                            Picker("Projection", selection: Binding(get: { graph.isSpatial }, set: { graph.isSpatial = $0 })) {
                                Text("2D").tag(false)
                                Text("3D").tag(true).disabled(graph.spatialUnavailableReason != nil)
                            }.pickerStyle(.segmented).frame(width: 90).contentShape(Rectangle())
                                .accessibilityIdentifier("result.projection")
                            Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                                if graph.isSpatial { graph.zoomToFit() }
                                else if graph.usesFeatureClusters { graph.clusterSession.cameraScale = 1; graph.clusterSession.cameraOffset = .zero }
                                else { graph.zoomToFit() }
                            }.contentShape(Rectangle())
                        }
                        if state.mode == .relationships && state.graphNames.count > 1 {
                            Picker("Graph", selection: $state.graphName) {
                                ForEach(state.graphNames, id: \.self) { graph in
                                    Text(graph.map { $0.term.description } ?? "Default graph").tag(graph)
                                }
                            }.frame(maxWidth: 180).contentShape(Rectangle())
                        }
                        if state.mode == .table {
                            Menu("Columns", systemImage: "rectangle.split.3x1") {
                                ForEach(state.columns.indices, id: \.self) { index in
                                    Toggle(state.columns[index], isOn: Binding(get: { state.visibleColumns.contains(index) }, set: { visible in
                                        if visible { state.visibleColumns.insert(index) } else { state.visibleColumns.remove(index) }
                                    })).contentShape(Rectangle())
                                }
                            }.contentShape(Rectangle()).accessibilityIdentifier("result.columns")
                        }
                        if state.mode == .analysis && !state.selectedIDs.isEmpty {
                            Button("Show in Table", systemImage: "tablecells") { state.mode = .table }
                                .contentShape(Rectangle()).accessibilityIdentifier("result.showTable")
                        }
                        Button("Coverage", systemImage: "info.circle") { showCoverage = true }
                            .contentShape(Rectangle()).popover(isPresented: $showCoverage) { coverage(state) }
                        Button("Raw", systemImage: "curlybraces") { showRaw = true }
                            .contentShape(Rectangle()).accessibilityIdentifier("result.raw")
                        Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                            .contentShape(Rectangle()).accessibilityIdentifier("result.inspector")
                    }
                }
                .inspector(isPresented: $showInspector) {
                    inspector(state).inspectorColumnWidth(min: 260, ideal: 340, max: 600)
                }
                .sheet(isPresented: $showRaw) { raw(state) }
                .onChange(of: state.selectedIDs) { _, selection in
                    state.synchronizeGraphSelection()
                    if !selection.isEmpty { showInspector = true }
                }
                .task(id: state.mode) {
                    if state.mode == .analysis { await state.prepareAnalysis() }
                    else if state.mode == .relationships { state.prepareRelationship() }
                }
                .onChange(of: state.graphName) { _, _ in state.prepareRelationship() }
                .onDisappear { state.cancel() }
        } else {
            ContentUnavailableView("Unable to Display Result", systemImage: "exclamationmark.triangle", description: Text(failure ?? "The result is invalid."))
        }
    }

    @ViewBuilder private func content(_ state: ResultPageState) -> some View {
        if state.originalRows.isEmpty {
            ContentUnavailableView("No Rows", systemImage: "tablecells", description: Text("The server returned an empty page."))
        } else {
            switch state.mode {
            case .table: ResultTableView(state: state)
            case .document: ResultDocumentView(state: state)
            case .analysis:
                if let graph = state.analysis { ResultGraphViewport(graph: graph, onSelect: state.selectAnalysisNode) }
                else if let failure = state.analysisFailure { ContentUnavailableView("Analysis Unavailable", systemImage: "chart.xyaxis.line", description: Text(failure)) }
                else { ProgressView("Preparing measurements…") }
            case .relationships:
                if let graph = state.relationship { ResultGraphViewport(graph: graph, onSelect: state.selectRelationshipNode) }
                else if let failure = state.relationshipFailure { ContentUnavailableView("Relationships Unavailable", systemImage: "exclamationmark.triangle", description: Text(failure)) }
                else { ProgressView("Preparing relationships…") }
            }
        }
    }

    @ViewBuilder private func inspector(_ state: ResultPageState) -> some View {
        if let row = state.selectedRows.first {
            Form {
                if state.selectedIDs.count > 1 {
                    Section("Selection") { Text("\(state.selectedIDs.count) rows selected. Showing original row \(row.id + 1).") }
                }
                Section("Row \(row.id + 1)") {
                    ForEach(state.columns.indices, id: \.self) { index in
                        ResultFieldView(name: state.columns[index], value: row.values[index])
                    }
                }
                if let canonical = row.canonical {
                    Section("Metadata") {
                        LabeledContent("Version", value: canonical.version.map { String(describing: $0) } ?? "Not provided")
                        Text(String(describing: canonical.annotations)).textSelection(.enabled)
                        Text("Result-page selection does not establish a persisted record identity.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped)
        } else { ContentUnavailableView("No Row Selected", systemImage: "doc.text.magnifyingglass") }
    }

    private func coverage(_ state: ResultPageState) -> some View {
        Form {
            Section("Current Result") {
                LabeledContent("Loaded rows", value: "\(state.originalRows.count)")
                Text(state.hasNextPage ? "More rows are available. Display and analysis cover only this loaded page." : "This response has no continuation. The result is not proof of complete collection coverage.")
                    .font(.caption)
                Text("Column headers order loaded rows only. Source filtering and ordering remain with Data/Query.").font(.caption)
            }
            if let dataset = state.analysisDataset {
                Section("Analysis Source") {
                    ForEach(dataset.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    ForEach(dataset.numericColumns, id: \.self) { key in
                        LabeledContent(key, value: "\(dataset.missingCounts[key, default: 0]) missing")
                    }
                }
            }
        }.formStyle(.grouped).frame(width: 440, height: 350)
    }

    private func raw(_ state: ResultPageState) -> some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(state.originalRows) { row in
                        Text(row.canonical.map { String(reflecting: $0) } ?? String(reflecting: state.quads[row.id]))
                            .textSelection(.enabled).accessibilityIdentifier("result.raw.\(row.id)")
                    }
                }.font(.system(.body, design: .monospaced)).padding()
            }
            .navigationTitle("Raw Result")
            .navigationSubtitle(state.coverage)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showRaw = false }.contentShape(Rectangle()) } }
        }.frame(minWidth: 650, minHeight: 450)
    }
}
