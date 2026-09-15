import XCTest
@testable import DatabaseStudioUI

@MainActor
final class RuntimeConnectionPersistenceTests: XCTestCase {
    func testHistoryPreservesIdentityAndKeepsDatabasesSeparate() throws {
        let suite = "DatabaseStudio.HistoryTest.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = RuntimeConnectionHistory(defaults: defaults)
        let endpoint = try XCTUnwrap(URL(string: "https://localhost/database"))
        let first = try history.record(endpoint: endpoint, databaseID: "one")
        let second = try history.record(endpoint: endpoint, databaseID: "two")
        let reused = try history.record(endpoint: endpoint, databaseID: "one")
        XCTAssertEqual(first.id, reused.id)
        XCTAssertNotEqual(first.id, second.id)
        let tenant = try history.record(endpoint: endpoint, databaseID: "one", tenantID: "tenant", workspaceID: "workspace")
        XCTAssertNotEqual(first.id, tenant.id)
        XCTAssertEqual(history.connections.count, 3)
        let reopened = RuntimeConnectionHistory(defaults: defaults)
        try reopened.load()
        XCTAssertEqual(reopened.connections, history.connections)
        let data = try XCTUnwrap(defaults.data(forKey: "RuntimeConnectionHistory"))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("accessToken"))
        try reopened.remove(first.id)
        XCTAssertEqual(reopened.connections.map(\.id), [tenant.id, second.id])
    }

    func testMalformedHistoryIsNotSilentlyOverwritten() throws {
        let suite = "DatabaseStudio.HistoryTest.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let malformed = Data("invalid".utf8)
        defaults.set(malformed, forKey: "RuntimeConnectionHistory")
        let history = RuntimeConnectionHistory(defaults: defaults)
        XCTAssertThrowsError(try history.record(endpoint: URL(string: "https://localhost/database")!, databaseID: "one"))
        XCTAssertEqual(defaults.data(forKey: "RuntimeConnectionHistory"), malformed)
    }

    func testNativeKeychainRoundTripUpdateAndRemoval() throws {
        let store = RuntimeCredentialStore(service: "DatabaseStudio.CredentialTest.\(UUID())")
        let id = UUID()
        defer {
            do { try store.remove(id) }
            catch { XCTFail("Credential cleanup failed: \(error)") }
        }
        XCTAssertNil(try store.token(for: id))
        try store.save("test-token-one", for: id)
        XCTAssertEqual(try store.token(for: id), "test-token-one")
        try store.save("test-token-two", for: id)
        XCTAssertEqual(try store.token(for: id), "test-token-two")
        try store.remove(id)
        XCTAssertNil(try store.token(for: id))
        try store.remove(id)
    }
}
