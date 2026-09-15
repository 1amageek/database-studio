import XCTest
import DatabaseWire
@testable import DatabaseStudioUI

@MainActor
final class RuntimeConnectionTests: XCTestCase {
    func testDisconnectedOperationsFailExplicitly() async {
        let connection = RuntimeConnection()
        do {
            _ = try await connection.execute(DatabaseOperationCatalog.capabilitiesDescribe, request: EmptyOperationPayload())
            XCTFail("A disconnected workspace must not execute operations")
        } catch RuntimeConnectionError.notConnected {
            XCTAssertFalse(connection.isConnected)
            XCTAssertNil(connection.capabilities)
            XCTAssertNil(connection.schema)
        } catch {
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testDisconnectIsIdempotent() async {
        let connection = RuntimeConnection()
        await connection.disconnect()
        await connection.disconnect()
        XCTAssertFalse(connection.isConnected)
        XCTAssertFalse(connection.isConnecting)
        XCTAssertNil(connection.capabilities)
        XCTAssertNil(connection.schema)
    }
}
