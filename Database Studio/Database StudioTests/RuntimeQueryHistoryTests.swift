import XCTest
import DatabaseWire
@testable import DatabaseStudioUI

@MainActor
final class RuntimeQueryHistoryTests: XCTestCase {
    func testScopeReopenDeduplicationAndCorruption() throws {
        let suite = "StudioQueryHistoryTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = RuntimeQueryHistory(defaults: defaults)
        let scope = ["https://example.invalid", "main", "tenant", "workspace"]
        try history.save(scope: scope, language: .sql, statement: "SELECT 1")
        try history.save(scope: scope, language: .sql, statement: "SELECT 1")
        try history.save(scope: ["https://example.invalid", "other", "tenant", "workspace"], language: .sparql, statement: "ASK {}")
        let reopened = RuntimeQueryHistory(defaults: defaults)
        try reopened.load()
        XCTAssertEqual(reopened.entries.count, 2)
        XCTAssertEqual(reopened.entries.last?.scope, scope)
        XCTAssertEqual(reopened.entries.last?.statement, "SELECT 1")
        let corrupt = Data("corrupt".utf8)
        defaults.set(corrupt, forKey: "RuntimeQueryHistory")
        XCTAssertThrowsError(try reopened.save(scope: scope, language: .sql, statement: "SELECT 2"))
        XCTAssertEqual(defaults.data(forKey: "RuntimeQueryHistory"), corrupt)
    }
}
