import Testing
@testable import DatabaseStudioUI

@MainActor
@Suite("AppViewModel Connection Error Presentation")
struct AppViewModelConnectionErrorTests {

    @Test("cluster unreachable is presented clearly")
    func clusterUnreachablePresentation() {
        let viewModel = AppViewModel.preview(
            connectionState: .error("Cannot connect to FDB server specified in /tmp/fdb.cluster. Ensure the server is running.")
        )

        #expect(viewModel.connectionErrorPresentation?.title == "Cluster Unreachable")
        #expect(viewModel.connectionErrorPresentation?.recoverySuggestion?.contains("running FoundationDB server") == true)
    }

    @Test("generic error falls back to Connection Failed")
    func genericErrorPresentation() {
        let viewModel = AppViewModel.preview(
            connectionState: .error("Something unexpected happened")
        )

        #expect(viewModel.connectionErrorPresentation?.title == "Connection Failed")
        #expect(viewModel.connectionErrorPresentation?.recoverySuggestion == nil)
    }

    @Test("no error presentation when connected")
    func noErrorWhenConnected() {
        let viewModel = AppViewModel.preview(connectionState: .connected)
        #expect(viewModel.connectionErrorPresentation == nil)
    }
}
