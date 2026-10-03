import XCTest
@testable import DatabaseStudioUI

final class AnalysisDatasetTests: XCTestCase {
    func testQuotedCSVTypesMissingValuesAndIdentity() throws {
        let data = Data("id,name,group,x,y\r\na,\"Line one\nLine two\",A,-2,\r\nb,\"A \"\"quoted\"\" name\",B,0,3\r\n".utf8)
        let result = try AnalysisDatasetReader().decode(data: data, sourceName: "measurements.csv", format: "csv")
        XCTAssertEqual(result.document.nodes.count, 2)
        XCTAssertEqual(result.document.nodes[0].label, "Line one\nLine two")
        XCTAssertEqual(result.document.nodes[1].label, "A \"quoted\" name")
        XCTAssertEqual(result.document.nodes[0].metrics["x"], -2)
        XCTAssertNil(result.document.nodes[0].metrics["y"])
        XCTAssertEqual(result.missingCounts["y"], 1)
        XCTAssertEqual(result.document.nodes[1].metadata["group"], "B")
    }

    func testJSONEnvelopeAndNullsPreserveProvenanceAndFlags() throws {
        let input = #"{"periodBasis":"unsynchronized snapshot","units":{"x":"USD"},"rows":[{"id":"a","company":"0.0030","metrics":{"x":null,"y":-2},"qualityFlags":["review"],"country":"JP"},{"id":"b","company":"Company","metrics":{"x":3,"y":4}}]}"#
        let result = try AnalysisDatasetReader().decode(data: Data(input.utf8), sourceName: "source.json", format: "json")
        XCTAssertEqual(result.numericColumns, ["x", "y"])
        XCTAssertEqual(result.missingCounts["x"], 1)
        XCTAssertTrue(result.provenance.contains("x: USD"))
        XCTAssertEqual(result.document.nodes[0].metadata["Quality flags"], "review")
        XCTAssertEqual(result.warnings.count, 2)
    }

    func testSemicolonHeadersIgnoreQuotedCommasAndRejectExcessColumns() throws {
        let data = Data("id;\"name, with, commas\";x\na;row;2\n".utf8)
        let result = try AnalysisDatasetReader().decode(data: data, sourceName: "rows.csv", format: "csv")
        XCTAssertEqual(result.document.nodes[0].metrics["x"], 2)
        let excessive = (0..<129).map { "column" + String($0) }.joined(separator: ",")
        XCTAssertThrowsError(try AnalysisDatasetReader().decode(data: Data(excessive.utf8), sourceName: "bad.csv", format: "csv"))
    }

    func testMalformedInputsFailWithoutSyntheticSuccess() throws {
        let reader = AnalysisDatasetReader()
        for input in ["id,x\na,1\na,2", "id,x\na,1,2", "id,x\na,\"1", "id,x\na,nan", "id,id\na,b"] {
            XCTAssertThrowsError(try reader.decode(data: Data(input.utf8), sourceName: "bad.csv", format: "csv"))
        }
        for input in [#"{"rows":[]}"#, #"[{"id":"","x":2}]"#, #"[{"id":"a","metrics":{"x":"invalid"}}]"#] {
            XCTAssertThrowsError(try reader.decode(data: Data(input.utf8), sourceName: "bad.json", format: "json"))
        }
    }
}
