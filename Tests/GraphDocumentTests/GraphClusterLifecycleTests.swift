import XCTest
@testable import DatabaseStudioUI

@MainActor
final class GraphClusterLifecycleTests: XCTestCase {
    private func fixture() async throws -> (GraphDocument, GraphClusterConfiguration, GraphClusterResult) {
        let document = GraphDocument(nodes: (0..<8).map {
            GraphNode(id: "n\($0)", label: "Value", role: .instance, metadata: ["Group": $0 < 4 ? "A" : "B"])
        })
        var configuration = GraphClusterConfiguration()
        configuration.metadataKeys = ["Group"]; configuration.clusterCount = 2
        let result = try await GraphFeatureAnalyzer().analyze(document: document, configuration: configuration)
        return (document, configuration, result)
    }

    func testCancelledDisplayConsumerRetainsSharedAnalysisForNextDisplay() async throws {
        let (document, configuration, result) = try await fixture()
        let analyzer = ControlledAnalyzer(), session = GraphClusterSession(analyzer: analyzer)
        session.configuration = configuration
        let chart = Task { await session.prepare(document: document) }
        await analyzer.started(1)
        chart.cancel()
        let spatial = Task { await session.prepare(document: document) }
        await analyzer.finish(1, result: result)
        await chart.value; await spatial.value
        XCTAssertEqual(session.result?.membership, result.membership, "A display consumer must not cancel the shared page-owned operation")
        XCTAssertFalse(session.isLoading, "Every terminal operation must leave the loading state")
        XCTAssertNil(session.failure)
        let calls = await analyzer.calls
        XCTAssertEqual(calls, 1, "Display switching must reuse one analysis")
    }

    func testOwnerCancellationRejectsLateCompletionAndAllowsRetry() async throws {
        let (document, configuration, result) = try await fixture()
        let analyzer = ControlledAnalyzer(), session = GraphClusterSession(analyzer: analyzer)
        session.configuration = configuration
        let old = Task { await session.prepare(document: document) }
        await analyzer.started(1)
        session.cancel()
        XCTAssertFalse(session.isLoading)
        XCTAssertNil(session.result)
        let retry = Task { await session.prepare(document: document) }
        await analyzer.started(2)
        await analyzer.finish(1, result: result)
        await old.value
        XCTAssertTrue(session.isLoading, "Late completion must not clear the replacement operation")
        XCTAssertNil(session.result)
        await analyzer.finish(2, result: result)
        await retry.value
        XCTAssertEqual(session.result?.membership, result.membership)
        XCTAssertFalse(session.isLoading)
        XCTAssertNil(session.failure)
    }

    func testFailureAfterConsumerCancellationRemainsRetryableByInvalidation() async throws {
        let (document, configuration, result) = try await fixture()
        let analyzer = ControlledAnalyzer(), session = GraphClusterSession(analyzer: analyzer)
        session.configuration = configuration
        let old = Task { await session.prepare(document: document) }
        await analyzer.started(1)
        old.cancel()
        await analyzer.fail(1)
        await old.value
        XCTAssertFalse(session.isLoading)
        XCTAssertNotNil(session.failure, "A page-owned analysis failure must remain explicit")
        session.invalidate()
        let retry = Task { await session.prepare(document: document) }
        await analyzer.started(2)
        await analyzer.finish(2, result: result)
        await retry.value
        XCTAssertNotNil(session.result)
        XCTAssertNil(session.failure)
        XCTAssertFalse(session.isLoading)
    }

    private actor ControlledAnalyzer: GraphClusterAnalyzing {
        private(set) var calls = 0
        private var continuations: [Int: CheckedContinuation<GraphClusterResult, any Error>] = [:]
        private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
        enum Failure: Error { case rejected }

        func analyze(document: GraphDocument, configuration: GraphClusterConfiguration) async throws -> GraphClusterResult {
            calls += 1
            let call = calls
            return try await withCheckedThrowingContinuation { continuation in
                continuations[call] = continuation
                waiters.removeValue(forKey: call)?.resume()
            }
        }
        func started(_ call: Int) async {
            if continuations[call] != nil { return }
            await withCheckedContinuation { waiters[call] = $0 }
        }
        func finish(_ call: Int, result: GraphClusterResult) { continuations.removeValue(forKey: call)?.resume(returning: result) }
        func fail(_ call: Int) { continuations.removeValue(forKey: call)?.resume(throwing: Failure.rejected) }
    }
}
