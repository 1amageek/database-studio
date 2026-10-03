import XCTest
import DatabaseKit
import DatabaseWire
@testable import DatabaseStudioUI

@MainActor
final class RecordAnalysisSourceTests: XCTestCase {
    func testTypedDocumentsPathsMissingnessAndRowReturn() async throws {
        let columns = [QueryColumn(number: 1, name: "doc"), QueryColumn(number: 2, name: "group")]
        let object = try FieldObject([("a/b", .float64(-2)), ("a~b", .int32(4)), ("flag", .bool(true)), ("nil", .null)])
        let rows = [DatabaseWire.QueryRow(values: [.object(object), .string("West")]), DatabaseWire.QueryRow(values: [.null, .string("East")])]
        let dataset = try await RecordAnalysisSource(columns: columns, rows: rows, hasNextPage: true).dataset()
        XCTAssertEqual(dataset.document.nodes[0].metrics["/doc/a~1b"], -2)
        XCTAssertEqual(dataset.document.nodes[0].metrics["/doc/a~0b"], 4)
        XCTAssertEqual(dataset.document.nodes[0].metadata["/doc/flag"], "true")
        XCTAssertEqual(dataset.missingCounts["/doc/a~1b"], 1)
        XCTAssertTrue(dataset.provenance.contains { $0.contains("this page only") })
        XCTAssertEqual(RecordAnalysisSource.rowIndex(dataset.document.nodes[1].id), 1)
        XCTAssertNil(RecordAnalysisSource.rowIndex("record:1"))
        XCTAssertEqual(rows[0].values[0], .object(object))
    }

    func testPrecisionAndUnsupportedValuesRemainInspectable() async throws {
        let names = ["exact", "inexact", "decimal", "array"]
        let columns = names.enumerated().map { QueryColumn(number: UInt32($0.offset), name: $0.element) }
        let row = DatabaseWire.QueryRow(values: [.int64(42), .uint64(UInt64.max), .decimal(.init(coefficient: 125, scale: 2)), .array([.int32(2)])])
        let dataset = try await RecordAnalysisSource(columns: columns, rows: [row], hasNextPage: false).dataset()
        XCTAssertEqual(dataset.document.nodes[0].metrics["/exact"], 42)
        XCTAssertEqual(dataset.document.nodes[0].metrics["/decimal"], 1.25)
        XCTAssertNil(dataset.document.nodes[0].metrics["/inexact"])
        XCTAssertTrue(dataset.warnings.contains { $0.contains("integer precision") })
        XCTAssertTrue(dataset.warnings.contains { $0.contains("approximate Double") })
        XCTAssertEqual(row.values[1], .uint64(UInt64.max))
    }

    func testInvalidInputsAndCancellationFail() async throws {
        let x = QueryColumn(number: 1, name: "x")
        let excessiveObject = try FieldObject((0..<129).map { (String($0), FieldValue.int32(1)) })
        let sources = [RecordAnalysisSource(columns: [x], rows: [.init(values: [.object(excessiveObject)])], hasNextPage: false),
                       RecordAnalysisSource(columns: [x, x], rows: [], hasNextPage: false),
                       RecordAnalysisSource(columns: [x], rows: [.init(values: [])], hasNextPage: false),
                       RecordAnalysisSource(columns: [x], rows: [.init(values: [.float64(.infinity)])], hasNextPage: false),
                       RecordAnalysisSource(columns: [x], rows: [.init(values: [.null])], hasNextPage: false),
                       RecordAnalysisSource(columns: [x], rows: Array(repeating: .init(values: [.int32(1)]), count: 10001), hasNextPage: false)]
        for source in sources {
            do { _ = try await source.dataset(); XCTFail("Expected an explicit failure") }
            catch { XCTAssertNotNil(error as? RecordAnalysisSource.Failure) }
        }
        let source = RecordAnalysisSource(columns: [x], rows: [.init(values: [.int32(1)])], hasNextPage: false)
        let task = Task { try await source.dataset() }; task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCanonical2000RowPageRunsNumericAnalysis() async throws {
        let columns = [QueryColumn(number: 1, name: "sales"), QueryColumn(number: 2, name: "profit"), QueryColumn(number: 3, name: "sector")]
        var rows: [DatabaseWire.QueryRow] = []
        for index in 0..<2000 {
            rows.append(.init(values: [.float64(Double(index + 1)), .float64(Double(index - 1000)), .string(index < 1000 ? "A" : "B")]))
        }
        let dataset = try await RecordAnalysisSource(columns: columns, rows: rows, hasNextPage: false).dataset()
        var configuration = GraphClusterConfiguration(); configuration.mode = .numeric; configuration.clusterCount = 4
        configuration.numericFeatures = [.init(numerator: "/sales", transform: .logarithm), .init(numerator: "/profit", denominator: "/sales", transform: .signedLogarithm)]
        let result = try await GraphNumericAnalyzer().analyze(document: dataset.document, configuration: configuration)
        XCTAssertEqual(result.membership.count, 2000); XCTAssertEqual(result.positions.count, 2000)
        XCTAssertEqual(rows.count, 2000)
        XCTAssertEqual(Set(result.membership.keys.compactMap(RecordAnalysisSource.rowIndex)), Set(0..<2000))
    }
}
