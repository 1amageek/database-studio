import XCTest
import Foundation
@testable import DatabaseStudioUI

@MainActor
final class ConnectionAccessTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "DatabaseStudio.ConnectionAccessTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    func testLocalPathsSurviveRestartAndPreserveIdentityAndFavorites() throws {
        try withDefaults { defaults in
            let store = ConnectionHistoryStore(defaults: defaults)
            try store.addOrUpdate(filePath: "/tmp/work/../history.db", rootDirectoryPath: "app/production")
            let first = try XCTUnwrap(store.mostRecent)
            try store.rename(first, to: "Production")
            try store.toggleFavorite(first)
            try store.addOrUpdate(filePath: "/tmp/history.db", rootDirectoryPath: "app/production")
            let reopened = ConnectionHistoryStore(defaults: defaults)
            let saved = try XCTUnwrap(reopened.mostRecent)
            XCTAssertEqual(saved.id, first.id)
            XCTAssertEqual(saved.filePath, "/tmp/history.db")
            XCTAssertEqual(saved.rootDirectoryPath, "app/production")
            XCTAssertEqual(saved.name, "Production")
            XCTAssertTrue(saved.isFavorite)
            XCTAssertEqual(saved.useCount, 2)
            XCTAssertEqual(reopened.connections.count, 1)
            XCTAssertNil(reopened.failure)
        }
    }

    func testRootPathsRemainSeparateAndFavoriteSurvivesHistoryLimit() throws {
        try withDefaults { defaults in
            let store = ConnectionHistoryStore(defaults: defaults)
            try store.addOrUpdate(filePath: "/tmp/shared.cluster", rootDirectoryPath: "one")
            let favorite = try XCTUnwrap(store.mostRecent)
            try store.toggleFavorite(favorite)
            try store.addOrUpdate(filePath: "/tmp/shared.cluster", rootDirectoryPath: "two")
            XCTAssertEqual(store.connections.count, 2)
            for index in 0..<12 { try store.addOrUpdate(filePath: "/tmp/history-\(index).db", rootDirectoryPath: "") }
            XCTAssertEqual(store.connections.count, 11)
            XCTAssertEqual(store.favorites.map(\.id), [favorite.id])
            try store.clearHistory()
            XCTAssertEqual(ConnectionHistoryStore(defaults: defaults).connections.map(\.id), [favorite.id])
        }
    }

    func testMalformedLocalHistoryCannotBeOverwrittenByAnyMutation() throws {
        try withDefaults { defaults in
            let data = Data("malformed history".utf8)
            defaults.set(data, forKey: "ConnectionHistory")
            let store = ConnectionHistoryStore(defaults: defaults)
            let entry = SavedDatabaseConnection(filePath: "/tmp/unused.db")
            XCTAssertNotNil(store.failure)
            XCTAssertThrowsError(try store.addOrUpdate(filePath: entry.filePath, rootDirectoryPath: ""))
            XCTAssertThrowsError(try store.remove(entry))
            XCTAssertThrowsError(try store.toggleFavorite(entry))
            XCTAssertThrowsError(try store.rename(entry, to: "Other"))
            XCTAssertThrowsError(try store.clearHistory())
            XCTAssertEqual(defaults.data(forKey: "ConnectionHistory"), data)
            defaults.set(try JSONEncoder().encode([entry]), forKey: "ConnectionHistory")
            try store.load()
            XCTAssertNil(store.failure)
            XCTAssertEqual(store.connections, [entry])
        }
    }

    func testLegacyLocalEntryRetainsItsIdentifierAfterSuccessfulAccess() throws {
        try withDefaults { defaults in
            let entry = SavedDatabaseConnection(name: "Existing", filePath: "/tmp/old/../database.sqlite", isFavorite: true, useCount: 7)
            defaults.set(try JSONEncoder().encode([entry]), forKey: "ConnectionHistory")
            let store = ConnectionHistoryStore(defaults: defaults)
            try store.addOrUpdate(filePath: "/tmp/database.sqlite", rootDirectoryPath: "")
            XCTAssertEqual(store.connections.count, 1)
            XCTAssertEqual(store.mostRecent?.id, entry.id)
            XCTAssertEqual(store.mostRecent?.useCount, 8)
            XCTAssertEqual(store.mostRecent?.name, "Existing")
        }
    }

    func testPreviousClusterFileHistoryMigratesWithoutLosingPreferences() throws {
        try withDefaults { defaults in
            let entry = SavedDatabaseConnection(name: "Saved Cluster", filePath: "/tmp/saved.cluster", rootDirectoryPath: "app/production", isFavorite: true, useCount: 9)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
            object["clusterFilePath"] = object.removeValue(forKey: "filePath")
            let previous = try JSONSerialization.data(withJSONObject: [object])
            defaults.set(previous, forKey: "ConnectionHistory")
            let store = ConnectionHistoryStore(defaults: defaults)
            XCTAssertNil(store.failure)
            XCTAssertEqual(store.mostRecent, entry)
            try store.addOrUpdate(filePath: entry.filePath, rootDirectoryPath: entry.rootDirectoryPath)
            XCTAssertEqual(store.mostRecent?.id, entry.id)
            XCTAssertEqual(store.mostRecent?.useCount, 10)
            XCTAssertEqual(store.mostRecent?.name, entry.name)
            XCTAssertEqual(store.mostRecent?.isFavorite, true)
            let saved = String(decoding: try XCTUnwrap(defaults.data(forKey: "ConnectionHistory")), as: UTF8.self)
            XCTAssertFalse(saved.contains("clusterFilePath"))
            XCTAssertTrue(saved.contains("filePath"))
        }
    }

    func testStartupChoosesNewestSuccessfulDestinationAndLocalOnTie() {
        let date = Date(timeIntervalSince1970: 100)
        let local = SavedDatabaseConnection(filePath: "/tmp/recent.db", lastUsed: date)
        let server = SavedRuntimeConnection(id: UUID(), endpoint: URL(string: "https://localhost/database")!, databaseID: "main", tenantID: nil, workspaceID: nil, lastUsed: date.addingTimeInterval(1))
        XCTAssertNil(ConnectionRestoration.destination(local: nil, server: nil))
        XCTAssertEqual(ConnectionRestoration.destination(local: local, server: nil), .local(local))
        XCTAssertEqual(ConnectionRestoration.destination(local: nil, server: server), .server(server.id))
        XCTAssertEqual(ConnectionRestoration.destination(local: local, server: server), .server(server.id))
        var older = server
        older.lastUsed = date.addingTimeInterval(-1)
        XCTAssertEqual(ConnectionRestoration.destination(local: local, server: older), .local(local))
        older.lastUsed = date
        XCTAssertEqual(ConnectionRestoration.destination(local: local, server: older), .local(local))
    }

    func testServerScopesSurviveRestartWithoutCredentials() throws {
        try withDefaults { defaults in
            let history = RuntimeConnectionHistory(defaults: defaults)
            let endpoint = URL(string: "https://localhost/database")!
            let first = try history.record(endpoint: endpoint, databaseID: "one", tenantID: "tenant", workspaceID: "workspace")
            let other = try history.record(endpoint: endpoint, databaseID: "two")
            let restored = try history.record(endpoint: endpoint, databaseID: "one", tenantID: "tenant", workspaceID: "workspace")
            XCTAssertEqual(restored.id, first.id)
            let reopened = RuntimeConnectionHistory(defaults: defaults)
            try reopened.load()
            XCTAssertEqual(reopened.connections.map(\.id), [first.id, other.id])
            XCTAssertEqual(reopened.connections.first?.tenantID, "tenant")
            XCTAssertEqual(reopened.connections.first?.workspaceID, "workspace")
            let text = String(decoding: try XCTUnwrap(defaults.data(forKey: "RuntimeConnectionHistory")), as: UTF8.self)
            XCTAssertFalse(text.contains("token"))
            XCTAssertFalse(text.contains("accessToken"))
        }
    }
}
