import XCTest
import DatabaseClient
import DatabaseClientHTTP
import DatabaseWire
@testable import DatabaseStudioUI

@MainActor
final class RuntimeServerTests: XCTestCase {
    private func configuration(tokenOverride: String? = nil) throws -> HTTPDatabaseConfiguration {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["STUDIO_RUNTIME_TEST_CREDENTIAL"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let endpoint = try XCTUnwrap(values["endpoint"] as? String)
        let token = try XCTUnwrap(values["token"] as? String)
        return try HTTPDatabaseConfiguration(endpoint: XCTUnwrap(URL(string: endpoint)),
                                             accessToken: tokenOverride ?? token, requestTimeout: 5)
    }

    func testRealHandshakeCatalogAndShutdown() async throws {
        let connection = RuntimeConnection()
        do {
            try await connection.connect(configuration: configuration())
            XCTAssertTrue(connection.isConnected)
            XCTAssertEqual(connection.capabilities?.runtimeVersion, "26.0904.0")
            XCTAssertNotNil(connection.schema)
            XCTAssertTrue(connection.capabilities?.features.contains { $0.identifier == "schema.execute" } == true)
            let capabilities = try await connection.execute(DatabaseOperationCatalog.capabilitiesDescribe,
                                                            request: EmptyOperationPayload())
            XCTAssertEqual(capabilities, connection.capabilities)
        } catch {
            await connection.disconnect()
            throw error
        }
        await connection.disconnect()
        XCTAssertFalse(connection.isConnected)
        do {
            _ = try await connection.execute(DatabaseOperationCatalog.capabilitiesDescribe, request: EmptyOperationPayload())
            XCTFail("Disconnected transport must not be used")
        } catch RuntimeConnectionError.notConnected {} catch { throw error }
    }

    func testRealServerRejectsInvalidCredentialWithoutPublishingCatalog() async throws {
        let connection = RuntimeConnection()
        do {
            try await connection.connect(configuration: configuration(tokenOverride: "invalid-test-token"))
            await connection.disconnect()
            XCTFail("Invalid credentials must fail")
        } catch let error as DatabaseClientError {
            guard case .transport(.rejected(let code, _)) = error else { throw error }
            XCTAssertEqual(code, "http_status_401")
        }
        XCTAssertFalse(connection.isConnected)
        XCTAssertNil(connection.schema)
        XCTAssertNil(connection.capabilities)
        XCTAssertFalse(connection.isConnecting)
        await connection.disconnect()
    }

    func testDisconnectDuringHandshakeDoesNotRepublish() async throws {
        let connection = RuntimeConnection()
        let configuration = try configuration()
        let task = Task { try await connection.connect(configuration: configuration) }
        await Task.yield()
        task.cancel()
        await connection.disconnect()
        do { try await task.value }
        catch is CancellationError {}
        catch let error as DatabaseClientError {
            guard case .transport(.cancelled) = error else { throw error }
        }
        XCTAssertFalse(connection.isConnected)
        XCTAssertNil(connection.schema)
        XCTAssertFalse(connection.isConnecting)
    }
}
