import XCTest
@testable import DatabaseStudioUI

@MainActor
final class GraphNumericAnalysisTests: XCTestCase {
    private var configuration: GraphClusterConfiguration {
        var c = GraphClusterConfiguration(); c.mode = .numeric; c.clusterCount = 2
        c.numericFeatures = [.init(numerator: "x"), .init(numerator: "y")]
        return c
    }
    private func document() -> GraphDocument {
        var nodes: [GraphNode] = []
        for index in 0..<9 {
            let group = index < 4 ? "A" : "B"
            let y = index < 4 ? index - 10 : index + 10
            let metrics: [String: Double] = ["x": Double(index - 4), "y": Double(y)]
            nodes.append(GraphNode(id: "n\(index)", label: "Node \(index)", role: .instance, metadata: ["group": group], metrics: metrics))
        }
        return GraphDocument(nodes: nodes)
    }

    func testNumericClusteringPreservesMagnitudesAndMedianRows() async throws {
        let result = try await GraphFeatureAnalyzer().analyze(document: document(), configuration: configuration)
        XCTAssertEqual(result.membership.count, 9)
        XCTAssertNotEqual(result.membership["n0"], result.membership["n8"])
        XCTAssertEqual(result.axes.count, 2)
        XCTAssertEqual(result.axes[0].value(at: -4), -1, accuracy: 1e-9)
        XCTAssertEqual(result.axes[0].value(at: 4), 1, accuracy: 1e-9)
        XCTAssertEqual(result.profiles.values.flatMap { $0 }.count, 4)
        var reversed = document(); reversed.nodes.reverse()
        let again = try await GraphNumericAnalyzer().analyze(document: reversed, configuration: configuration)
        XCTAssertEqual(result.membership, again.membership); XCTAssertEqual(result.positions, again.positions)
    }

    func testRatioTransformsMissingnessAndFlagsAreExplicit() async throws {
        var c = configuration; c.numericFeatures = [.init(numerator: "profit", denominator: "sales", transform: .signedLogarithm)]
        var nodes: [GraphNode] = []
        for index in 0..<7 {
            let flags: [String: String] = index == 6 ? ["Quality flags": "review"] : [:]
            let values: [String: Double] = ["profit": Double(index - 2), "sales": index == 5 ? 0 : 10]
            nodes.append(GraphNode(id: "n\(index)", label: "Row", role: .instance, metadata: flags, metrics: values))
        }
        let result = try await GraphNumericAnalyzer().analyze(document: .init(nodes: nodes), configuration: c)
        XCTAssertEqual(result.membership.count, 5); XCTAssertNotNil(result.membership["n2"])
        XCTAssertEqual(result.unassignedIDs, ["n5", "n6"])
        XCTAssertEqual(result.exclusionReasons.count, 2)
        XCTAssertEqual(result.positions.count, 7)
        XCTAssertEqual(c.numericFeatures[0].value(in: nodes[0]), -0.2)
        c.numericFeatures[0].transform = .logarithm
        let positive = try await GraphNumericAnalyzer().analyze(document: .init(nodes: nodes), configuration: c)
        XCTAssertEqual(positive.membership.count, 2)
    }

    func testPCADoesNotChangeMembershipAndPeerCenteringRemovesGroupOffsets() async throws {
        var c = configuration
        var nodes: [GraphNode] = []
        for group in 0..<2 { for value in 0..<6 { nodes.append(GraphNode(id: "\(group)-\(value)", label: "Row", role: .instance,
            metadata: ["group": String(group)], metrics: ["x": Double(group * 100 + value), "y": Double(value)])) } }
        let document = GraphDocument(nodes: nodes)
        let base = try await GraphNumericAnalyzer().analyze(document: document, configuration: c)
        c.projection = .pca
        let pca = try await GraphNumericAnalyzer().analyze(document: document, configuration: c)
        XCTAssertEqual(base.membership, pca.membership); XCTAssertGreaterThan(pca.retainedVariance, 0.99)
        c.projection = .axes; c.comparisonKey = "group"
        let peers = try await GraphNumericAnalyzer().analyze(document: document, configuration: c)
        let first = try XCTUnwrap(peers.positions["0-0"]), second = try XCTUnwrap(peers.positions["1-0"])
        XCTAssertEqual(first.x, second.x, accuracy: 1e-10); XCTAssertEqual(first.y, second.y, accuracy: 1e-10)
        XCTAssertEqual(peers.membership["0-0"], peers.membership["1-0"])
    }

    func testEmptyConstantCapacityAndCancellationFail() async throws {
        for document in [GraphDocument(), GraphDocument(nodes: (0..<3).map { .init(id: String($0), label: "Row", role: .instance, metrics: ["x": 1, "y": 1]) })] {
            do { _ = try await GraphNumericAnalyzer().analyze(document: document, configuration: configuration); XCTFail("Expected failure") } catch { XCTAssertNotNil(error as? GraphFeatureAnalyzer.Failure) }
        }
        let excessive = GraphDocument(nodes: (0...GraphNumericAnalyzer.maximumNodes).map { GraphNode(id: String($0), label: "Row", role: .instance) })
        do { _ = try await GraphNumericAnalyzer().analyze(document: excessive, configuration: configuration); XCTFail("Expected capacity failure") }
        catch { guard case GraphFeatureAnalyzer.Failure.capacity = error else { return XCTFail("Wrong capacity error: \(error)") } }
        let document = document(), c = configuration
        let task = Task { try await GraphNumericAnalyzer().analyze(document: document, configuration: c) }; task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testFull2000CompanySnapshot() async throws {
        guard let path = ProcessInfo.processInfo.environment["ANALYSIS_FINANCIAL_FIXTURE"] else { throw XCTSkip("The retained local dataset is not a bundled package fixture.") }
        let dataset = try await AnalysisDatasetReader().read(url: URL(fileURLWithPath: path))
        XCTAssertEqual(dataset.document.nodes.count, 2000)
        var c = configuration; c.clusterCount = 8
        c.numericFeatures = [.init(numerator: "netProfitUSD", denominator: "revenueUSD", transform: .signedLogarithm),
                             .init(numerator: "revenueUSD", denominator: "assetsUSD", transform: .logarithm),
                             .init(numerator: "marketValueUSD", denominator: "revenueUSD", transform: .logarithm)]
        let clock = ContinuousClock(), start = clock.now
        let result = try await GraphNumericAnalyzer().analyze(document: dataset.document, configuration: c)
        print("2000-company numeric analysis: \(start.duration(to: clock.now)), \(result.iterations) iterations")
        XCTAssertEqual(result.membership.count, 1996); XCTAssertEqual(result.unassignedIDs.count, 4)
        XCTAssertEqual(result.positions.count, 2000); XCTAssertEqual(result.clusters.count, 8)
        XCTAssertTrue(result.positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        XCTAssertTrue(dataset.warnings.contains { $0.contains("labels are entirely numeric") })
    }
}
