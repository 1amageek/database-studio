import XCTest
@testable import DatabaseStudioUI

final class WorkspaceDestinationTests: XCTestCase {
    func testServerRestorationRetainsTheExactHistoryIdentity() throws {
        let id = UUID()
        let destination = ConnectionRestoration.server(id).workspaceDestination
        let encoded = try JSONEncoder().encode(destination)
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceDestination.self, from: encoded), .server(id))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("token"))
    }

    func testLocalRestorationRetainsPathRootAndPreferences() throws {
        let entry = SavedDatabaseConnection(name: "Research", filePath: "/tmp/research.sqlite", rootDirectoryPath: "companies", isFavorite: true, useCount: 8)
        let destination = ConnectionRestoration.local(entry).workspaceDestination
        let restored = try JSONDecoder().decode(WorkspaceDestination.self, from: JSONEncoder().encode(destination))
        guard case .database(let value) = restored else { return XCTFail("Expected the saved database destination") }
        XCTAssertEqual(value?.id, entry.id)
        XCTAssertEqual(value?.filePath, entry.filePath)
        XCTAssertEqual(value?.rootDirectoryPath, "companies")
        XCTAssertEqual(value?.useCount, 8)
        XCTAssertEqual(value?.isFavorite, true)
    }
}
