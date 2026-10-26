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

    func testEveryPrimitiveKindHasReadableNonDebugText() throws {
        let date = try CivilDate(year: 2000, month: 2, day: 29)
        let time = try CivilTime(hour: 1, minute: 2, second: 3, nanoseconds: 450_000_000)
        XCTAssertEqual(ResultValueFormat.text(FieldValue.date(date)), "2000-02-29")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.time(time)), "01:02:03.45")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.dateTime(.init(date: date, time: time))), "2000-02-29T01:02:03.45")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.timestamp(.init(secondsSinceUnixEpoch: 0))), "1970-01-01T00:00:00Z")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.timestamp(.init(secondsSinceUnixEpoch: 951_782_400))), "2000-02-29T00:00:00Z")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.timestamp(.init(secondsSinceUnixEpoch: 1_761_440_523))), "2025-10-26T01:02:03Z")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.timestamp(try .init(secondsSinceUnixEpoch: -1, nanoseconds: 500_000_000))),
            "1969-12-31T23:59:59.5Z")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.timestamp(.init(secondsSinceUnixEpoch: -62_135_596_800))), "0001-01-01T00:00:00Z")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.timestamp(.init(secondsSinceUnixEpoch: -62_135_596_801))), "0000-12-31T23:59:59Z")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.timeSpan(try .init(seconds: -1, nanoseconds: 500_000_000))), "-0.5 s")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.timeSpan(try .init(seconds: 90))), "90 s")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.calendarPeriod(.init(months: 14, days: -3))), "14 months -3 days")
        XCTAssertEqual(ResultValueFormat.text(FieldValue.vector(Vector(int8: [1, 2, 3]))), "3 × int8 vector")
        let reference = try EntityReference(entity: "Order", id: .composite([.string("A"), .int64(7)]))
        XCTAssertEqual(ResultValueFormat.text(FieldValue.reference(reference)), "Order · (A, 7)")
        XCTAssertEqual(ResultValueFormat.hex(ByteString([0x00, 0xab, 0x10])), "00ab10")
        XCTAssertEqual(ResultValueFormat.hex(ByteString()), "empty")
    }

    func testRawRowRetainsKindsVersionAndAnnotations() throws {
        let annotations = try FieldObject([("source", .string("primary")), ("score", .int64(3))])
        let row = QueryRow(values: [.primitive(.timestamp(.init(secondsSinceUnixEpoch: 0))), .primitive(.bytes(ByteString([1, 255]))),
            .primitive(.null)], annotations: annotations, version: ByteString([0, 0, 0, 9]))
        let text = ResultRawText.row(row, columns: ["at", "payload", "missing"])
        XCTAssertEqual(text, """
            at = timestamp(1970-01-01T00:00:00Z)
            payload = bytes(01ff)
            missing = null
            version = bytes(00000009)
            annotations = {score: int64(3), source: string("primary")}
            """)
        XCTAssertFalse(text.contains("FieldObject("))
        XCTAssertFalse(text.contains("ByteString("))
        XCTAssertEqual(ResultRawText.row(QueryRow(values: []), columns: []), "version = none\nannotations = {}")
    }
}
