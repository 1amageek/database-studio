import XCTest
import DatabaseKit
import DatabaseWire
@testable import DatabaseStudioUI

@MainActor
final class RecordAnalysisSourceTests: XCTestCase {
    func testTypedDocumentsPathsMissingnessAndRowReturn() async throws {
        let columns = try [QueryColumn(number: 1, name: "doc", type: .primitive(.object), isNullable: true), QueryColumn(number: 2, name: "group", type: .primitive(.string), isNullable: true)]
        let object = try FieldObject([("a/b", .float64(-2)), ("a~b", .int32(4)), ("flag", .bool(true)), ("nil", .null)])
        let rows = [DatabaseWire.QueryRow(values: [.object(object), .string("West")].map(DatabaseKit.QueryValue.primitive)), DatabaseWire.QueryRow(values: [.null, .string("East")].map(DatabaseKit.QueryValue.primitive))]
        let dataset = try await RecordAnalysisSource(columns: columns, rows: rows, hasNextPage: true).dataset()
        XCTAssertEqual(dataset.document.nodes[0].metrics["/doc/a~1b"], -2)
        XCTAssertEqual(dataset.document.nodes[0].metrics["/doc/a~0b"], 4)
        XCTAssertEqual(dataset.document.nodes[0].metadata["/doc/flag"], "true")
        XCTAssertEqual(dataset.missingCounts["/doc/a~1b"], 1)
        XCTAssertTrue(dataset.provenance.contains { $0.contains("this page only") })
        XCTAssertEqual(RecordAnalysisSource.rowIndex(dataset.document.nodes[1].id), 1)
        XCTAssertNil(RecordAnalysisSource.rowIndex("record:1"))
        XCTAssertEqual(rows[0].values[0], .primitive(.object(object)))
    }

    func testPrecisionAndUnsupportedValuesRemainInspectable() async throws {
        let names = ["exact", "inexact", "decimal", "array"]
        let types: [QueryColumnType] = [.primitive(.int64), .primitive(.uint64), .primitive(.decimal), .primitive(.int32, isArray: true)]
        let columns = try names.enumerated().map { try QueryColumn(number: UInt32($0.offset + 1), name: $0.element, type: types[$0.offset], isNullable: true) }
        let row = DatabaseWire.QueryRow(values: [.int64(42), .uint64(UInt64.max), .decimal(.init(coefficient: 125, scale: 2)), .array([.int32(2)])].map(DatabaseKit.QueryValue.primitive))
        let dataset = try await RecordAnalysisSource(columns: columns, rows: [row], hasNextPage: false).dataset()
        XCTAssertEqual(dataset.document.nodes[0].metrics["/exact"], 42)
        XCTAssertEqual(dataset.document.nodes[0].metrics["/decimal"], 1.25)
        XCTAssertNil(dataset.document.nodes[0].metrics["/inexact"])
        XCTAssertTrue(dataset.warnings.contains { $0.contains("integer precision") })
        XCTAssertTrue(dataset.warnings.contains { $0.contains("approximate Double") })
        XCTAssertEqual(row.values[1], .primitive(.uint64(UInt64.max)))
    }

    func testInvalidInputsAndCancellationFail() async throws {
        let x = try QueryColumn(number: 1, name: "x", type: .primitive(.float64), isNullable: true)
        let excessiveObject = try FieldObject((0..<129).map { (String($0), FieldValue.int32(1)) })
        let sources = [RecordAnalysisSource(columns: [x], rows: [.init(values: [.object(excessiveObject)].map(DatabaseKit.QueryValue.primitive))], hasNextPage: false),
                       RecordAnalysisSource(columns: [x, x], rows: [], hasNextPage: false),
                       RecordAnalysisSource(columns: [x], rows: [.init(values: [].map(DatabaseKit.QueryValue.primitive))], hasNextPage: false),
                       RecordAnalysisSource(columns: [x], rows: [.init(values: [.float64(.infinity)].map(DatabaseKit.QueryValue.primitive))], hasNextPage: false),
                       RecordAnalysisSource(columns: [x], rows: [.init(values: [.null].map(DatabaseKit.QueryValue.primitive))], hasNextPage: false),
                       RecordAnalysisSource(columns: [x], rows: Array(repeating: .init(values: [.int32(1)].map(DatabaseKit.QueryValue.primitive)), count: 10001), hasNextPage: false)]
        for source in sources {
            do { _ = try await source.dataset(); XCTFail("Expected an explicit failure") }
            catch { XCTAssertNotNil(error as? RecordAnalysisSource.Failure) }
        }
        let source = RecordAnalysisSource(columns: [x], rows: [.init(values: [.int32(1)].map(DatabaseKit.QueryValue.primitive))], hasNextPage: false)
        let task = Task { try await source.dataset() }; task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCanonical2000RowPageRunsNumericAnalysis() async throws {
        let columns = try [QueryColumn(number: 1, name: "sales", type: .primitive(.float64), isNullable: true), QueryColumn(number: 2, name: "profit", type: .primitive(.float64), isNullable: true), QueryColumn(number: 3, name: "sector", type: .primitive(.string), isNullable: true)]
        var rows: [DatabaseWire.QueryRow] = []
        for index in 0..<2000 {
            rows.append(.init(values: [.float64(Double(index + 1)), .float64(Double(index - 1000)), .string(index < 1000 ? "A" : "B")].map(DatabaseKit.QueryValue.primitive)))
        }
        let dataset = try await RecordAnalysisSource(columns: columns, rows: rows, hasNextPage: false).dataset()
        var configuration = GraphClusterConfiguration(); configuration.mode = .numeric; configuration.clusterCount = 4
        configuration.numericFeatures = [.init(numerator: "/sales", transform: .logarithm), .init(numerator: "/profit", denominator: "/sales", transform: .signedLogarithm)]
        let result = try await GraphNumericAnalyzer().analyze(document: dataset.document, configuration: configuration)
        XCTAssertEqual(result.membership.count, 2000); XCTAssertEqual(result.positions.count, 2000)
        XCTAssertEqual(rows.count, 2000)
        XCTAssertEqual(Set(result.membership.keys.compactMap(RecordAnalysisSource.rowIndex)), Set(0..<2000))
    }

    func testRDFNumericLiteralsRetainCanonicalValuesAndLexicalCategories() async throws {
        let xsd = "http://www.w3.org/2001/XMLSchema#"
        let values: [FieldValue] = [
            .rdfTerm(.literal(try RDFLiteral(lexicalForm: "-42", datatype: xsd + "integer"))),
            .rdfTerm(.literal(try RDFLiteral(lexicalForm: "0", datatype: xsd + "integer"))),
            .rdfTerm(.literal(try RDFLiteral(lexicalForm: "1.25", datatype: xsd + "decimal"))),
            .rdfTerm(.literal(try RDFLiteral(lexicalForm: "2.5e2", datatype: xsd + "double"))),
            .rdfTerm(.literal(try RDFLiteral(lexicalForm: "9007199254740993", datatype: xsd + "integer"))),
            .rdfTerm(.literal(try RDFLiteral(lexicalForm: "Banking", datatype: xsd + "string")))
        ]
        let columns = try values.indices.map { try QueryColumn(number: UInt32($0 + 1), name: "c\($0)", type: .primitive(.rdfTerm), isNullable: true) }
        let row = DatabaseWire.QueryRow(values: values.map(DatabaseKit.QueryValue.primitive))
        let dataset = try await RecordAnalysisSource(columns: columns, rows: [row], hasNextPage: false).dataset()
        XCTAssertEqual(dataset.document.nodes[0].metrics["/c0"], -42)
        XCTAssertEqual(dataset.document.nodes[0].metrics["/c1"], 0)
        XCTAssertEqual(dataset.document.nodes[0].metrics["/c2"], 1.25)
        XCTAssertEqual(dataset.document.nodes[0].metrics["/c3"], 250)
        XCTAssertNil(dataset.document.nodes[0].metrics["/c4"])
        XCTAssertEqual(dataset.document.nodes[0].metadata["/c5"], "Banking")
        XCTAssertEqual(row.values, values.map(DatabaseKit.QueryValue.primitive))
        XCTAssertTrue(dataset.warnings.contains { $0.contains("integer precision") })
        XCTAssertTrue(dataset.warnings.contains { $0.contains("approximate Double") })
    }

    func testMalformedAndNonfiniteRDFMeasurementsFailExplicitly() async throws {
        for lexical in ["not a number", "NaN", "INF", "0x1p0", "1e999"] {
            let literal = try RDFLiteral(lexicalForm: lexical, datatype: "http://www.w3.org/2001/XMLSchema#double")
            do {
                _ = try await RecordAnalysisSource(columns: [.init(number: 1, name: "value", type: .primitive(.rdfTerm), isNullable: true)], rows: [.init(values: [.rdfTerm(.literal(literal))].map(DatabaseKit.QueryValue.primitive))], hasNextPage: false).dataset()
                XCTFail("Malformed measurements must not become synthetic zero values")
            } catch { XCTAssertNotNil(error as? RecordAnalysisSource.Failure) }
        }
    }
}
