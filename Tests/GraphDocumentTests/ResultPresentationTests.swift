import XCTest
import DatabaseKit
import DatabaseWire
@testable import DatabaseStudioUI

@MainActor
final class ResultPresentationTests: XCTestCase {
    private var columns: [QueryColumn] { [.init(number: 1, name: "sales"), .init(number: 2, name: "sector")] }

    func testNativePageOrderingPreservesExactValuesAndSelection() throws {
        let input: [DatabaseWire.QueryRow] = [
            .init(values: [.uint64(UInt64.max), .string("A")]),
            .init(values: [.uint64(UInt64.max - 1), .string("B")]),
            .init(values: [.uint64(2), .string("C")]),
            .init(values: [.uint64(2), .string("D")])]
        let state = try ResultPageState(columns: columns, rows: input, hasNextPage: true)
        state.selectedIDs = [0, 1]
        state.sortOrder = [.init(column: 0)]
        XCTAssertEqual(state.orderedRows.map(\.id), [2, 3, 1, 0])
        XCTAssertEqual(state.selectedRows.map(\.id), [0, 1])
        XCTAssertEqual(state.selectedRows.first?.canonical?.values[0], .uint64(UInt64.max))
        state.sortOrder = [.init(column: 0, order: .reverse)]
        XCTAssertEqual(state.orderedRows.map(\.id), [0, 1, 2, 3])
        state.visibleColumns.remove(0)
        state.mode = .document
        XCTAssertEqual(state.selectedIDs, [0, 1])
        XCTAssertTrue(state.hasNextPage)
        XCTAssertEqual(state.availableModes, [.table, .document, .analysis])
    }

    func testNewPageDefaultsToTableAndDoesNotReuseDuplicateSelection() throws {
        let row = DatabaseWire.QueryRow(values: [.int64(42), .string("A")])
        let first = try ResultPageState(columns: columns, rows: [row, row], hasNextPage: true)
        first.mode = .analysis; first.selectedIDs = [1]
        let next = try ResultPageState(columns: columns, rows: [row, row], hasNextPage: false)
        XCTAssertEqual(next.mode, .table)
        XCTAssertTrue(next.selectedIDs.isEmpty)
        XCTAssertEqual(next.originalRows.map(\.id), [0, 1])
        XCTAssertThrowsError(try ResultPageState(columns: columns, rows: [.init(values: [])], hasNextPage: false)) { error in
            XCTAssertNotNil(error as? ResultPageState.Failure)
        }
    }

    func testReadableFormattingRetainsExactDecimalAndNestedValues() throws {
        XCTAssertEqual(ResultValueFormat.text(.decimal(.init(coefficient: -125, scale: 2))), "-1.25")
        XCTAssertEqual(ResultValueFormat.text(.decimal(.init(coefficient: Int128(Int64.min), scale: 0))), "-9223372036854775808")
        XCTAssertEqual(ResultValueFormat.text(.decimal(.init(coefficient: 1, scale: 12))), "0.000000000001")
        XCTAssertEqual(ResultValueFormat.text(.decimal(.init(coefficient: 1, scale: Int32.min))), "1e2147483648")
        XCTAssertEqual(ResultValueFormat.text(.string("Example")), "Example")
        XCTAssertEqual(ResultValueFormat.text(.null), "NULL")
        let object = try FieldObject([("nested", .array([.uint64(UInt64.max), .null]))])
        let state = try ResultPageState(columns: [.init(number: 1, name: "doc")], rows: [.init(values: [.object(object)])], hasNextPage: false)
        XCTAssertEqual(state.originalRows[0].values[0], .object(object))
        XCTAssertEqual(state.originalRows[0].canonical?.values[0], .object(object))
    }

    func testRelationshipScopeAndIncidentSelectionDoNotMergeNamedGraphs() throws {
        let subject = RDFSubject.iri(try RDFIRI("urn:subject"))
        let predicate = try RDFPredicateIRI("urn:related")
        let object = RDFTerm.iri(try RDFIRI("urn:object"))
        let graph = try RDFGraphName(iri: "urn:graph")
        let quads = [RDFQuad(subject: subject, predicate: predicate, object: object),
                     RDFQuad(subject: subject, predicate: predicate, object: .iri(try RDFIRI("urn:other")), graph: graph)]
        let state = ResultPageState(quads: quads, hasNextPage: true)
        XCTAssertEqual(state.availableModes, [.table, .document, .relationships])
        XCTAssertEqual(state.graphNames.count, 2)
        state.selectedIDs = [0]
        state.prepareRelationship()
        XCTAssertEqual(state.relationship?.selectedNodeID, "urn:subject")
        state.selectRelationshipNode("urn:subject")
        XCTAssertEqual(state.selectedIDs, [0])
        XCTAssertEqual(state.relationship?.document.edges.count, 1)
        state.selectRelationshipNode("urn:subject")
        XCTAssertEqual(state.selectedIDs, [0])
        state.graphName = graph
        state.prepareRelationship()
        state.relationship?.selectNode("urn:subject")
        state.selectRelationshipNode("urn:subject")
        XCTAssertEqual(state.selectedIDs, [1])
        XCTAssertEqual(state.originalRows[1].values[3], .rdfTerm(graph.term))
        state.selectedIDs = [0]
        state.synchronizeGraphSelection()
        XCTAssertNil(state.relationship?.selectedNodeID)
        state.selectRelationshipNode(nil)
        XCTAssertEqual(state.selectedIDs, [0], "A programmatic graph deselection must preserve an out-of-scope table row")
    }

    func testNumericModesShareOriginalRowIdentityAfterSorting() async throws {
        var input: [DatabaseWire.QueryRow] = []
        for index in 0..<2000 { input.append(.init(values: [.int64(Int64(index + 1)), .string(index < 1000 ? "A" : "B")])) }
        let state = try ResultPageState(columns: columns, rows: input, hasNextPage: false)
        state.selectedIDs = [1500]
        state.sortOrder = [.init(column: 0, order: .reverse)]
        state.mode = .analysis
        await state.prepareAnalysis()
        XCTAssertNil(state.analysisFailure)
        XCTAssertEqual(state.analysisDataset?.document.nodes.count, 2000)
        XCTAssertEqual(state.analysis?.selectedNodeID, "page-row:1500")
        state.selectAnalysisNode("page-row:100")
        state.mode = .table
        XCTAssertEqual(state.selectedRows.first?.id, 100)
        XCTAssertEqual(state.selectedRows.first?.canonical?.values[0], .int64(101))
        XCTAssertEqual(state.orderedRows.first?.id, 1999)
        state.selectAnalysisNode("page-row:999999")
        XCTAssertTrue(state.selectedIDs.isEmpty)
    }

    func testAnalysisFailureAndCancelledPreparationPublishNoSyntheticSuccess() async throws {
        let state = try ResultPageState(columns: columns, rows: [.init(values: [.null, .string("A")])], hasNextPage: false)
        await state.prepareAnalysis()
        XCTAssertNotNil(state.analysisFailure)
        XCTAssertNil(state.analysis)
        XCTAssertEqual(state.originalRows.count, 1)
        let pending = try ResultPageState(columns: columns, rows: [.init(values: [.int64(1), .string("A")])], hasNextPage: false)
        let task = Task { await pending.prepareAnalysis() }
        task.cancel()
        await task.value
        XCTAssertNil(pending.analysis)
        XCTAssertNil(pending.analysisDataset)
        XCTAssertFalse(pending.isPreparingAnalysis)
        XCTAssertNil(pending.analysisFailure)
    }
}
