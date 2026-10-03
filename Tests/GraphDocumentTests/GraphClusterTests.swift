import XCTest
import simd
@testable import DatabaseStudioUI

@MainActor
final class GraphClusterTests: XCTestCase {
    private func populations() -> GraphDocument {
        GraphDocument(nodes: (0..<8).map { GraphNode(id: "n\($0)", label: "Node \($0)", role: .instance,
                                                   metadata: ["Category": $0 < 4 ? "A" : "B", "Common": "shared"]) }, edges: [])
    }

    private var categories: GraphClusterConfiguration {
        var c = GraphClusterConfiguration(); c.clusterCount = 2; c.metadataKeys = ["Category", "Common"]; return c
    }

    func testFeaturePopulationsAndProjectionAreIndependentAndDeterministic() async throws {
        var document = populations()
        let result = try await GraphFeatureAnalyzer().analyze(document: document, configuration: categories)
        XCTAssertEqual(result.clusters.count, 2)
        XCTAssertEqual(result.membership["n0"], result.membership["n3"])
        XCTAssertNotEqual(result.membership["n0"], result.membership["n4"])
        XCTAssertEqual(result.positions["n0"], result.positions["n3"])
        XCTAssertNotEqual(result.positions["n0"], result.positions["n4"])
        XCTAssertEqual(result.featureCount, 2)
        XCTAssertEqual(result.retainedVariance, 1, accuracy: 1e-8)
        XCTAssertTrue(result.positions.values.allSatisfy { abs($0.y) < 1e-8 })
        XCTAssertTrue(result.clusters.flatMap(\.features).contains("Category: A"))
        document.nodes.reverse()
        let reversed = try await GraphFeatureAnalyzer().analyze(document: document, configuration: categories)
        XCTAssertEqual(result.membership, reversed.membership)
        XCTAssertEqual(result.positions, reversed.positions)
    }

    func testRelationshipFeaturesUseExactIdentitiesAndContextUsesOriginalNeighbors() async throws {
        var document = populations()
        document.nodes.append(GraphNode(id: "a", label: "Same label", role: .property))
        document.nodes.append(GraphNode(id: "b", label: "Same label", role: .property))
        document.nodes.append(GraphNode(id: "unknown", label: "Unknown", role: .instance))
        document.nodes.append(GraphNode(id: "isolated", label: "Isolated", role: .type))
        document.edges = (0..<8).map { GraphEdge(id: "e\($0)", sourceID: "n\($0)", targetID: $0 < 4 ? "a" : "b", label: "same", ontologyProperty: $0 < 4 ? "urn:first" : "urn:second") }
        var c = GraphClusterConfiguration(); c.clusterCount = 2; c.typeWeight = 0
        let result = try await GraphFeatureAnalyzer().analyze(document: document, configuration: c)
        XCTAssertNotEqual(result.membership["n0"], result.membership["n4"])
        XCTAssertEqual(result.positions["a"], result.positions["n0"])
        XCTAssertEqual(result.positions["b"], result.positions["n4"])
        XCTAssertEqual(result.unassignedIDs, ["unknown"])
        XCTAssertEqual(result.unpositionedIDs, ["unknown", "isolated"])
        XCTAssertEqual(Set(result.positions.keys), Set(document.nodes.map(\.id)))
        XCTAssertEqual(document.edges.count, 8)
    }

    func testFeatureWeightsChangeTheComparedResponsibility() async throws {
        var document = populations()
        for index in document.nodes.indices { document.nodes[index].ontologyClass = index.isMultiple(of: 2) ? "Even" : "Odd" }
        var c = categories; c.typeWeight = 8; c.attributeWeight = 0
        let typed = try await GraphFeatureAnalyzer().analyze(document: document, configuration: c)
        XCTAssertEqual(typed.membership["n0"], typed.membership["n4"])
        c.typeWeight = 0; c.attributeWeight = 8
        let attributed = try await GraphFeatureAnalyzer().analyze(document: document, configuration: c)
        XCTAssertNotEqual(attributed.membership["n0"], attributed.membership["n4"])
    }

    func testNumericMissingnessDiffersFromMeasuredZero() async throws {
        let nodes = (0..<5).map { GraphNode(id: "n\($0)", label: "Value", role: .instance, metrics: $0 < 4 ? ["value": $0 < 2 ? 0 : 1] : [:]) }
        var c = GraphClusterConfiguration(); c.clusterCount = 3; c.metricKeys = ["value"]
        let result = try await GraphFeatureAnalyzer().analyze(document: GraphDocument(nodes: nodes, edges: []), configuration: c)
        XCTAssertEqual(result.clusters.count, 3)
        XCTAssertNotEqual(result.membership["n0"], result.membership["n4"])
        XCTAssertNotEqual(result.membership["n2"], result.membership["n4"])
        XCTAssertTrue(result.clusters.flatMap(\.features).contains("Missing value"))
    }

    func testCommonAndUniqueOnlyFeaturesFailExplicitly() async {
        let document = GraphDocument(nodes: (0..<4).map { GraphNode(id: "n\($0)", label: "Node", role: .instance, metadata: ["Common": "same", "Unique": "\($0)"]) }, edges: [])
        var c = GraphClusterConfiguration(); c.metadataKeys = ["Common", "Unique"]
        do { _ = try await GraphFeatureAnalyzer().analyze(document: document, configuration: c); XCTFail("Uninformative data succeeded") }
        catch GraphFeatureAnalyzer.Failure.noFeatures { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testInvalidGraphConfigurationAndMetricsAreRejected() async {
        var duplicate = populations(); duplicate.nodes.append(duplicate.nodes[0])
        var missing = populations(); missing.edges.append(GraphEdge(id: "missing", sourceID: "n0", targetID: "absent", label: "related"))
        var invalidMetric = populations(); invalidMetric.nodes[0].metrics["bad"] = .infinity
        var invalidConfiguration = categories; invalidConfiguration.relationshipWeight = .nan
        var metricConfiguration = categories; metricConfiguration.metricKeys = ["bad"]
        let excess = GraphDocument(nodes: (0...1000).map { GraphNode(id: "x\($0)", label: "X", role: .instance) }, edges: [])
        for (document, configuration) in [(duplicate, categories), (missing, categories), (invalidMetric, metricConfiguration), (populations(), invalidConfiguration), (excess, categories)] {
            do { _ = try await GraphFeatureAnalyzer().analyze(document: document, configuration: configuration); XCTFail("Invalid input succeeded") }
            catch is GraphFeatureAnalyzer.Failure { }
            catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    func testCancellationCannotPublishSuccess() async {
        let document = populations(), configuration = categories
        let task = Task { try await GraphFeatureAnalyzer().analyze(document: document, configuration: configuration) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled analysis succeeded") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testSessionRetainsReadyResultAndInvalidatesConfigurationAndDocument() async throws {
        let session = GraphClusterSession(); session.configuration = categories
        await session.prepare(document: populations())
        let result = try XCTUnwrap(session.result), revision = session.revision
        session.selectedCluster = 0; session.cancel()
        await session.prepare(document: populations())
        XCTAssertEqual(session.result?.positions, result.positions)
        XCTAssertEqual(session.revision, revision)
        XCTAssertEqual(session.emphasizedIDs.count, 4)
        XCTAssertTrue(session.coordinateCenter.x.isFinite && session.coordinateCenter.y.isFinite)
        XCTAssertGreaterThan(session.coordinateExtent.x, 0); XCTAssertGreaterThan(session.coordinateExtent.y, 0)
        session.configuration.typeWeight = 0
        XCTAssertNil(session.result); XCTAssertNil(session.selectedCluster)
        await session.prepare(document: populations()); XCTAssertNotNil(session.result)
        session.invalidate(); XCTAssertNil(session.result); XCTAssertFalse(session.isLoading)
    }

    func testSupersededCompletionCannotReplaceNewResult() async throws {
        let analyzer = ControlledAnalyzer()
        let session = GraphClusterSession(analyzer: analyzer)
        session.configuration = categories
        let old = Task { await session.prepare(document: populations()) }
        await analyzer.started(2)
        session.configuration.clusterCount = 3
        let current = Task { await session.prepare(document: populations()) }
        await analyzer.started(3)
        let result = try await GraphFeatureAnalyzer().analyze(document: populations(), configuration: session.configuration)
        let oldResult = try await GraphFeatureAnalyzer().analyze(document: populations(), configuration: categories)
        await analyzer.finish(3, result: result); await current.value
        await analyzer.finish(2, result: oldResult); await old.value
        XCTAssertEqual(session.result?.configuration.clusterCount, 3)
        XCTAssertFalse(session.isLoading); XCTAssertNil(session.failure)
    }

    func testResearchedThousandEntityFeaturePath() async throws {
        let document = try await AutomotiveGraphSnapshot.load(), start = ContinuousClock.now
        let result = try await GraphFeatureAnalyzer().analyze(document: document, configuration: GraphClusterConfiguration())
        print("FEATURE_ANALYSIS_1000 seconds=\(start.duration(to: .now)) features=\(result.featureCount) clusters=\(result.clusters.count) variance=\(result.retainedVariance) unassigned=\(result.unassignedIDs.count) iterations=\(result.iterations)")
        XCTAssertEqual(result.positions.count, 1000)
        XCTAssertGreaterThan(result.clusters.count, 1)
        XCTAssertTrue(result.positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        XCTAssertFalse(result.clusters.flatMap(\.features).contains { $0.contains("License") || $0.contains("Source URL") })
        XCTAssertEqual(result.clusters.flatMap(\.members).count + result.unassignedIDs.count, document.nodes.filter { $0.role == .instance }.count)
        XCTAssertEqual(document.edges.count, 2584)
    }

    private actor ControlledAnalyzer: GraphClusterAnalyzing {
        private var continuations: [Int: CheckedContinuation<GraphClusterResult, any Error>] = [:]
        private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
        func analyze(document: GraphDocument, configuration: GraphClusterConfiguration) async throws -> GraphClusterResult {
            try await withCheckedThrowingContinuation { continuation in
                continuations[configuration.clusterCount] = continuation
                waiters.removeValue(forKey: configuration.clusterCount)?.resume()
            }
        }
        func started(_ count: Int) async {
            if continuations[count] != nil { return }
            await withCheckedContinuation { waiters[count] = $0 }
        }
        func finish(_ count: Int, result: GraphClusterResult) { continuations.removeValue(forKey: count)?.resume(returning: result) }
    }
}
