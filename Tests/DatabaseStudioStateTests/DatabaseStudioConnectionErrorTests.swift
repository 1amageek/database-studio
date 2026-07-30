import Testing
@testable import DatabaseStudioUI

@MainActor
@Suite("DatabaseStudioState Connection Error Presentation")
struct DatabaseStudioConnectionErrorTests {

    @Test("cluster unreachable is presented clearly")
    func clusterUnreachablePresentation() {
        let studioState = DatabaseStudioState.sample(
            connectionState: .error("Cannot connect to FDB server specified in /tmp/fdb.cluster. Ensure the server is running.")
        )

        #expect(studioState.connectionErrorPresentation?.title == "Cluster Unreachable")
        #expect(studioState.connectionErrorPresentation?.recoverySuggestion?.contains("running FoundationDB server") == true)
    }

    @Test("generic error falls back to Connection Failed")
    func genericErrorPresentation() {
        let studioState = DatabaseStudioState.sample(
            connectionState: .error("Something unexpected happened")
        )

        #expect(studioState.connectionErrorPresentation?.title == "Connection Failed")
        #expect(studioState.connectionErrorPresentation?.recoverySuggestion == nil)
    }

    @Test("no error presentation when connected")
    func noErrorWhenConnected() {
        let studioState = DatabaseStudioState.sample(connectionState: .connected)
        #expect(studioState.connectionErrorPresentation == nil)
    }
}
