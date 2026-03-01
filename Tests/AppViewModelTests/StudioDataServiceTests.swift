import Testing
import Foundation
@testable import DatabaseStudioUI

@MainActor
@Suite("StudioDataService Guard Behavior")
struct StudioDataServiceTests {

    // MARK: - Disconnected state throws notConnected

    @Test("findAll throws notConnected when disconnected")
    func findAllThrowsWhenDisconnected() async {
        let service = StudioDataService()
        await #expect(throws: StudioError.self) {
            _ = try await service.findAll(typeName: "Test")
        }
    }

    @Test("getItem throws notConnected when disconnected")
    func getItemThrowsWhenDisconnected() async {
        let service = StudioDataService()
        await #expect(throws: StudioError.self) {
            _ = try await service.getItem(typeName: "Test", id: "1")
        }
    }

    @Test("insertItem throws notConnected when disconnected")
    func insertItemThrowsWhenDisconnected() async {
        let service = StudioDataService()
        await #expect(throws: StudioError.self) {
            try await service.insertItem(typeName: "Test", dict: ["id": "1"])
        }
    }

    @Test("deleteItem throws notConnected when disconnected")
    func deleteItemThrowsWhenDisconnected() async {
        let service = StudioDataService()
        await #expect(throws: StudioError.self) {
            try await service.deleteItem(typeName: "Test", id: "1")
        }
    }

    @Test("collectionStats throws notConnected when disconnected")
    func collectionStatsThrowsWhenDisconnected() async {
        let service = StudioDataService()
        await #expect(throws: StudioError.self) {
            _ = try await service.collectionStats(typeName: "Test")
        }
    }

    @Test("loadEntities throws notConnected when disconnected")
    func loadEntitiesThrowsWhenDisconnected() async {
        let service = StudioDataService()
        await #expect(throws: StudioError.self) {
            try await service.loadEntities()
        }
    }

    @Test("loadOntology throws notConnected when disconnected")
    func loadOntologyThrowsWhenDisconnected() async {
        let service = StudioDataService()
        await #expect(throws: StudioError.self) {
            _ = try await service.loadOntology()
        }
    }

    // MARK: - Post-disconnect throws

    @Test("data access throws after disconnect")
    func dataAccessThrowsAfterDisconnect() async {
        let service = StudioDataService()

        // Connect to a temporary SQLite database
        let tmpPath = "/tmp/test-svc-\(UUID()).sqlite"
        await service.connect(filePath: tmpPath)
        #expect(service.connectionState == .connected)

        // Disconnect
        service.disconnect()
        #expect(service.connectionState == .disconnected)

        // All data access methods must throw
        await #expect(throws: StudioError.self) {
            _ = try await service.findAll(typeName: "Test")
        }
        await #expect(throws: StudioError.self) {
            try await service.loadEntities()
        }

        // Clean up
        try? FileManager.default.removeItem(atPath: tmpPath)
    }

    // MARK: - Idempotency

    @Test("disconnect is idempotent")
    func disconnectIdempotent() {
        let service = StudioDataService()
        service.disconnect()
        service.disconnect()
        #expect(service.connectionState == .disconnected)
    }

    // MARK: - Connection state

    @Test("initial state is disconnected")
    func initialStateDisconnected() {
        let service = StudioDataService()
        #expect(service.connectionState == .disconnected)
        #expect(service.entities.isEmpty)
    }

    @Test("connect to SQLite sets connected state")
    func connectSQLiteSetsConnected() async {
        let service = StudioDataService()
        let tmpPath = "/tmp/test-svc-connect-\(UUID()).sqlite"

        await service.connect(filePath: tmpPath)
        #expect(service.connectionState == .connected)

        service.disconnect()
        try? FileManager.default.removeItem(atPath: tmpPath)
    }
}
