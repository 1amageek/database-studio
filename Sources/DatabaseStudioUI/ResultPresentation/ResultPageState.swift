import Foundation
import Observation
import DatabaseKit
import DatabaseWire

/// Owns presentation identity and state for exactly one retained result page.
@Observable @MainActor
final class ResultPageState {
    enum Mode: String, CaseIterable { case table = "Table", document = "Document", relationships = "Relationships", analysis = "Analysis" }
    enum Failure: Error, LocalizedError {
        case invalidRow
        var errorDescription: String? { "A result row does not match its declared columns." }
    }

    let columns: [String]
    let sourceColumns: [QueryColumn]
    let sourceRows: [DatabaseWire.QueryRow]
    let quads: [RDFQuad]
    let originalRows: [ResultPageRow]
    let hasNextPage: Bool
    let isRDF: Bool
    var mode = Mode.table
    var selectedIDs = Set<Int>()
    var sortOrder = [ResultSortComparator(column: -1)] {
        didSet { reorder() }
    }
    private(set) var orderedRows: [ResultPageRow]
    var visibleColumns: Set<Int>
    var analysis: GraphViewState?
    var analysisDataset: AnalysisDataset?
    var analysisFailure: String?
    var isPreparingAnalysis = false
    var relationship: GraphViewState?
    var relationshipFailure: String?
    var graphName: RDFGraphName? {
        didSet { if graphName != oldValue { relationship = nil; relationshipFailure = nil } }
    }
    private var preparationGeneration: UInt64 = 0
    private var synchronizedRelationshipID: String?
    private var hasRelationshipSelectionEcho = false

    init(columns: [QueryColumn], rows: [DatabaseWire.QueryRow], hasNextPage: Bool) throws {
        guard rows.allSatisfy({ $0.values.count == columns.count }) else { throw Failure.invalidRow }
        self.columns = columns.map(\.name)
        sourceColumns = columns
        sourceRows = rows
        quads = []
        isRDF = false
        self.hasNextPage = hasNextPage
        // One identity wrapper per row shares the existing canonical field backing.
        originalRows = rows.enumerated().map { ResultPageRow(index: $0.offset, row: $0.element) }
        orderedRows = originalRows
        visibleColumns = Set(columns.indices)
    }

    init(quads: [RDFQuad], hasNextPage: Bool) {
        columns = ["Subject", "Predicate", "Object", "Graph"]
        sourceColumns = []
        sourceRows = []
        self.quads = quads
        isRDF = true
        self.hasNextPage = hasNextPage
        originalRows = quads.enumerated().map { ResultPageRow(index: $0.offset, quad: $0.element) }
        orderedRows = originalRows
        visibleColumns = Set(0..<4)
        graphName = quads.first?.graph
    }

    var availableModes: [Mode] { isRDF ? [.table, .document, .relationships] : [.table, .document, .analysis] }
    var selectedRows: [ResultPageRow] { selectedIDs.sorted().compactMap { originalRows.indices.contains($0) ? originalRows[$0] : nil } }
    var graphNames: [RDFGraphName?] {
        Array(Set(quads.map(\.graph))).sorted { left, right in
            switch (left, right) { case (nil, _?): true; case (_?, nil): false; case let (left?, right?): left < right; default: false }
        }
    }
    var activeGraph: GraphViewState? { mode == .analysis ? analysis : mode == .relationships ? relationship : nil }
    var coverage: String { "\(originalRows.count) loaded rows" + (hasNextPage ? " · More available" : " · Current result") }

    private func reorder() {
        orderedRows.sort { left, right in
            for comparator in sortOrder {
                let result = comparator.compare(left, right)
                if result != .orderedSame { return result == .orderedAscending }
            }
            return left.id < right.id
        }
    }

    func selectAnalysisNode(_ id: String?) {
        selectedIDs = id.flatMap(RecordAnalysisSource.rowIndex).map { originalRows.indices.contains($0) ? Set([$0]) : [] } ?? []
    }

    func selectRelationshipNode(_ id: String?) {
        if hasRelationshipSelectionEcho, id == synchronizedRelationshipID {
            hasRelationshipSelectionEcho = false; synchronizedRelationshipID = nil; return
        }
        hasRelationshipSelectionEcho = false
        synchronizedRelationshipID = nil
        guard let id else { selectedIDs = []; return }
        selectedIDs = Set(quads.indices.filter { index in
            let quad = quads[index]
            return quad.graph == graphName && (identity(quad.subject.term) == id || identity(quad.object) == id)
        })
    }

    private func identity(_ term: RDFTerm) -> String {
        if case .iri(let iri) = term { return iri.rawValue }
        return term.description
    }

    func synchronizeGraphSelection() {
        if let graph = relationship {
            let id = selectedIDs.sorted().first { quads.indices.contains($0) && quads[$0].graph == graphName }.map { identity(quads[$0].subject.term) }
            if graph.selectedNodeID != id {
                synchronizedRelationshipID = id
                hasRelationshipSelectionEcho = true
                graph.selectNode(id)
            }
        }
        if let graph = analysis {
            let id = selectedIDs.min().map { "page-row:\($0)" }
            if graph.selectedNodeID != id { graph.selectNode(id) }
        }
    }

    func prepareRelationship() {
        guard relationship == nil, relationshipFailure == nil else { return }
        do {
            let document = try RuntimeGraphPage(quads: quads).document(in: graphName)
            relationship = GraphViewState(document: document, showsAllNodes: true)
            synchronizeGraphSelection()
        } catch { relationshipFailure = "This graph contains an unsupported RDF term. Table, Document and Raw remain available. " + String(describing: error) }
    }

    func prepareAnalysis() async {
        guard analysis == nil, !isPreparingAnalysis else { return }
        preparationGeneration &+= 1
        let generation = preparationGeneration
        isPreparingAnalysis = true
        analysisFailure = nil
        defer { if generation == preparationGeneration { isPreparingAnalysis = false } }
        do {
            let dataset = try await RecordAnalysisSource(columns: sourceColumns, rows: sourceRows, hasNextPage: hasNextPage).dataset()
            try Task.checkCancellation()
            guard generation == preparationGeneration else { return }
            analysisDataset = dataset
            analysis = GraphViewState(document: dataset.document, showsAllNodes: true, numericAnalysis: true)
            synchronizeGraphSelection()
        } catch is CancellationError { }
        catch { if generation == preparationGeneration { analysisFailure = error.localizedDescription } }
    }

    func cancel() {
        preparationGeneration &+= 1
        isPreparingAnalysis = false
        analysis?.clusterSession.cancel()
        relationship?.stopSimulation()
    }
}
