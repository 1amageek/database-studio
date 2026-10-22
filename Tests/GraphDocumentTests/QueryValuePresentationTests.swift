import DatabaseKit
import DatabaseWire
import XCTest
@testable import DatabaseStudioUI

@MainActor
final class QueryValuePresentationTests: XCTestCase {
    private let limits = QueryValueLimits(maximumRetainedBytes: 1_048_576,
        maximumTotalNodes: 1000, maximumNestingDepth: 16, maximumCollectionElements: 1000)

    func testSQLNumericRetainsScaleAndExactOrdering() throws {
        let exact = try QueryNumericValue(value: .init(coefficient: 125, scale: 2), displayScale: 4)
        let smaller = try QueryNumericValue(value: .init(coefficient: 124, scale: 2), displayScale: 4)
        let rows = [QueryRow(values: [.numeric(exact)]), QueryRow(values: [.numeric(smaller)])]
        let column = try QueryColumn(number: 1, name: "amount", type: .sql(.decimal(precision: nil, scale: nil)), isNullable: true)
        let state = try ResultPageState(columns: [column], rows: rows, hasNextPage: false)
        state.sortOrder = [.init(column: 0)]
        XCTAssertEqual(state.orderedRows.map(\.id), [1, 0])
        XCTAssertEqual(state.originalRows[0].values, rows[0].values)
        XCTAssertEqual(ResultValueFormat.text(.numeric(exact)), "1.2500")
        let largeScale = try QueryNumericValue(value: exact.value, displayScale: 16_383)
        XCTAssertEqual(ResultValueFormat.text(.numeric(largeScale)), "1.25 (scale 16383)")
    }

    func testSQLArrayBoundsRemainCanonicalWithoutInventedLocalOrdering() throws {
        let array = try QueryArrayValue(elementType: .integer,
            dimensions: [.init(lowerBound: -2, length: 2)],
            elements: [.primitive(.int32(2)), .primitive(.int32(1))], limits: limits)
        let value = DatabaseKit.QueryValue.array(array)
        let column = try QueryColumn(number: 1, name: "items", type: .sql(.array(.integer)), isNullable: true)
        let state = try ResultPageState(columns: [column], rows: [.init(values: [value])], hasNextPage: false)
        XCTAssertEqual(state.originalRows[0].values[0], value)
        XCTAssertEqual(array.dimensions[0].lowerBound, -2)
        XCTAssertEqual(ResultValueFormat.text(value), "2 elements · [-2:-1]")
        XCTAssertFalse(state.sortableColumns.contains(0))
        state.sortOrder = [.init(column: 0)]
        XCTAssertEqual(state.orderedRows.map(\.id), [0])
    }

    func testSQLCompositeNumericProjectionPreservesUnsupportedValues() async throws {
        let amount = try QueryNumericValue(value: .init(coefficient: 125, scale: 1), displayScale: 2)
        let type = try QueryCompositeType(columns: [
            .init(number: 1, name: "amount", type: .sql(.decimal(precision: nil, scale: nil)), isNullable: true)], limits: limits)
        let composite = try QueryCompositeValue(type: type, fields: [.numeric(amount)], limits: limits)
        let json = try QueryJSONValue(bytes: ByteString(Array("{\"x\":1}".utf8)), limits: limits)
        let row = QueryRow(values: [.composite(composite), .json(json)])
        let columns = try [QueryColumn(number: 1, name: "record", type: .sql(.composite(type)), isNullable: true),
            QueryColumn(number: 2, name: "json", type: .sql(.json), isNullable: true)]
        let dataset = try await RecordAnalysisSource(columns: columns, rows: [row], hasNextPage: false).dataset()
        XCTAssertEqual(dataset.document.nodes[0].metrics["/record/amount"], 12.5)
        XCTAssertNil(dataset.document.nodes[0].metrics["/json"])
        XCTAssertTrue(dataset.warnings.contains { $0.contains("/json") })
        XCTAssertEqual(row.values, [.composite(composite), .json(json)])
    }

    func testTemporalAndJSONBPresentationRetainsTypeSpecificValues() throws {
        let time = try QueryTimeValue(microsecondsSinceMidnight: 86_400_000_000)
        XCTAssertEqual(ResultValueFormat.text(.time(time)), "24:00:00.000000")
        XCTAssertEqual(ResultValueFormat.text(.timeWithTimeZone(.init(time: time, utcOffsetSeconds: -1800))),
            "24:00:00.000000-00:30:00")
        XCTAssertEqual(ResultValueFormat.text(.dateInfinity(.negative)), "-infinity")
        XCTAssertEqual(ResultValueFormat.text(.timestampInfinity(.positive, withTimeZone: true)), "infinity")
        let numeric = try QueryNumericValue(value: .init(coefficient: 12, scale: 1), displayScale: 3)
        XCTAssertEqual(ResultValueFormat.jsonb(.number(numeric)), "1.200")
        XCTAssertFalse(ResultValueFormat.isNumeric(.time(time)))
        XCTAssertEqual(ResultValueFormat.jsonb(.null), "null")
        XCTAssertEqual(ResultValueFormat.jsonb(.string("null")), "\"null\"")
    }
}
