import XCTest
import DatabaseKit
import DatabaseWire
@testable import DatabaseStudioUI

@MainActor
final class AnalysisChartTests: XCTestCase {
    private func state(projector: any AnalysisChartProjecting = AnalysisChartProjection()) async throws -> ResultPageState {
        let columns: [QueryColumn] = try [.init(number: 1, name: "sales", type: .primitive(.int64), isNullable: true),
                                          .init(number: 2, name: "profit", type: .primitive(.int64), isNullable: true)]
        var rows: [DatabaseWire.QueryRow] = []
        for index in 0..<20 {
            let profit: FieldValue = index == 19 ? .null : .int64(Int64(index - 8))
            rows.append(.init(values: [.int64(Int64(index * index + 1)), profit].map(DatabaseKit.QueryValue.primitive)))
        }
        let state = try ResultPageState(columns: columns, rows: rows, hasNextPage: true, chartProjector: projector)
        state.mode = .analysis
        await state.prepareAnalysis()
        let graph = try XCTUnwrap(state.analysis)
        var configuration = graph.clusterSession.configuration
        configuration.numericFeatures = [.init(numerator: "/sales", transform: .logarithm), .init(numerator: "/profit", transform: .signedLogarithm)]
        configuration.clusterCount = 3
        graph.clusterSession.configuration = configuration
        await state.prepareCharts()
        return state
    }

    func testScatterInvertsAxesAndPreservesExcludedRows() async throws {
        let state = try await state()
        let data = try XCTUnwrap(state.currentChartData), result = try XCTUnwrap(state.analysis?.clusterSession.result)
        XCTAssertEqual(data.points.count, 19)
        XCTAssertEqual(data.excludedCount, 1)
        XCTAssertFalse(data.points.contains { $0.id == 19 })
        for point in data.points {
            let position = try XCTUnwrap(result.positions["page-row:\(point.id)"])
            XCTAssertEqual(point.x, result.axes[0].value(at: position.x), accuracy: 1e-12)
            XCTAssertEqual(point.y, result.axes[1].value(at: position.y), accuracy: 1e-12)
            XCTAssertEqual(point.clusterID, result.membership["page-row:\(point.id)"])
        }
        XCTAssertTrue(data.xTitle.contains("Log10"))
        XCTAssertTrue(data.yTitle.contains("Asinh"))
        XCTAssertEqual(state.originalRows.count, 20)
        XCTAssertTrue(state.hasNextPage)
    }

    func testCountsAndQuartilesUseExactAnalysisPopulationAndOriginalValues() async throws {
        let state = try await state()
        let data = try XCTUnwrap(state.currentChartData), result = try XCTUnwrap(state.analysis?.clusterSession.result)
        XCTAssertEqual(data.groups.reduce(0) { $0 + $1.rowIDs.count }, 19)
        XCTAssertEqual(data.features.count, 2)
        for group in data.groups {
            let cluster = try XCTUnwrap(result.clusters.first { $0.id == group.id })
            XCTAssertEqual(group.rowIDs, cluster.members.compactMap(RecordAnalysisSource.rowIndex).sorted())
            for feature in data.features {
                let profile = try XCTUnwrap(feature.profiles.first { $0.id == group.id })
                let source = try XCTUnwrap(result.profiles[group.id]?.first { $0.id == feature.id })
                XCTAssertEqual(profile.median, source.median)
                XCTAssertEqual(profile.lowerQuartile, source.lowerQuartile)
                XCTAssertEqual(profile.upperQuartile, source.upperQuartile)
                XCTAssertEqual(feature.populationMedian, source.populationMedian)
            }
        }
        XCTAssertGreaterThan(data.features[0].populationMedian, 10, "Profiles must retain original amounts, not robust units")
    }

    func testPCAChartRetainsSharedXYAndMembership() async throws {
        let state = try await state(), graph = try XCTUnwrap(state.analysis)
        let original = try XCTUnwrap(graph.clusterSession.result).membership
        graph.clusterSession.configuration.projection = .pca
        XCTAssertNil(state.currentChartData)
        await state.prepareCharts()
        let result = try XCTUnwrap(graph.clusterSession.result), data = try XCTUnwrap(state.currentChartData)
        XCTAssertEqual(result.membership, original)
        XCTAssertTrue(data.xTitle.contains("Principal component 1"))
        for point in data.points {
            let position = try XCTUnwrap(result.positions["page-row:\(point.id)"])
            XCTAssertEqual(point.x, position.x)
            XCTAssertEqual(point.y, position.y)
        }
    }

    func testChartSelectionSurvivesSortingAndModeChanges() async throws {
        let state = try await state(), data = try XCTUnwrap(state.currentChartData)
        state.sortOrder = [.init(column: 0, order: .reverse)]
        state.selectChartRow(3)
        state.synchronizeGraphSelection()
        XCTAssertEqual(state.analysis?.selectedNodeID, "page-row:3")
        XCTAssertEqual(state.selectedRows.first?.canonical?.values[0], .primitive(.int64(10)))
        let group = try XCTUnwrap(data.groups.first)
        state.selectAnalysisCluster(group.id)
        state.synchronizeGraphSelection()
        XCTAssertEqual(state.selectedIDs, Set(group.rowIDs))
        state.chartKind = .profiles; state.chartFeatureID = data.features.last?.id
        state.mode = .table; state.mode = .analysis
        XCTAssertEqual(state.selectedIDs, Set(group.rowIDs))
        XCTAssertEqual(state.chartKind, .profiles)
        XCTAssertEqual(state.chartFeatureID, data.features.last?.id)
        state.selectChartRow(19)
        XCTAssertEqual(state.selectedIDs, [19], "Excluded rows remain inspectable from the original table")
        XCTAssertNil(state.analysis?.clusterSession.selectedCluster)
        state.selectChartRow(99999)
        XCTAssertTrue(state.selectedIDs.isEmpty)
    }

    func testChartPreferencesAnd3DSwitchReuseProjectionUntilConfigurationChanges() async throws {
        let projector = CountingProjection(), state = try await state(projector: projector)
        let graph = try XCTUnwrap(state.analysis)
        state.chartKind = .counts
        graph.isSpatial = true; graph.isSpatial = false
        state.mode = .table; state.mode = .analysis
        await state.prepareCharts()
        let count = await projector.calls
        XCTAssertEqual(count, 1)
        graph.clusterSession.configuration.clusterCount = 2
        XCTAssertNil(state.currentChartData)
        await state.prepareCharts()
        let updated = await projector.calls
        XCTAssertEqual(updated, 2)
        XCTAssertEqual(state.currentChartData?.groups.count, 2)
    }

    func testMalformedCoordinatesFailAndCancellationPublishesNoChart() async throws {
        let state = try await state(), result = try XCTUnwrap(state.analysis?.clusterSession.result)
        var positions = result.positions
        positions["page-row:0"] = SIMD2(.nan, 0)
        let malformed = GraphClusterResult(configuration: result.configuration, clusters: result.clusters, membership: result.membership,
                                         positions: positions, unpositionedIDs: result.unpositionedIDs, unassignedIDs: result.unassignedIDs,
                                         featureCount: result.featureCount, retainedVariance: result.retainedVariance, iterations: result.iterations,
                                         axes: result.axes, exclusionReasons: result.exclusionReasons, profiles: result.profiles)
        do { _ = try await AnalysisChartProjection().project(malformed, rowCount: 20); XCTFail("Expected invalid result") }
        catch { XCTAssertNotNil(error as? AnalysisChartProjection.Failure) }
        do { _ = try await AnalysisChartProjection().project(result, rowCount: 5); XCTFail("Expected row identity failure") }
        catch { XCTAssertNotNil(error as? AnalysisChartProjection.Failure) }
        let cancelled = Task { try await AnalysisChartProjection().project(result, rowCount: 20) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        state.analysis?.clusterSession.configuration.clusterCount = 2
        let preparation = Task { await state.prepareCharts() }
        preparation.cancel(); await preparation.value
        XCTAssertNil(state.currentChartData)
        XCTAssertNil(state.chartFailure)
        XCTAssertFalse(state.isPreparingCharts)
    }

    func testProjectionFailureRetainsCanonicalRowsAndAnalysis() async throws {
        let state = try await state(projector: RejectingProjection())
        XCTAssertNil(state.currentChartData)
        XCTAssertNotNil(state.chartFailure)
        XCTAssertEqual(state.originalRows.count, 20)
        XCTAssertNotNil(state.analysis?.clusterSession.result)
        state.mode = .table
        XCTAssertEqual(state.originalRows[0].canonical?.values[0], .primitive(.int64(1)))
    }

    private actor CountingProjection: AnalysisChartProjecting {
        private(set) var calls = 0
        func project(_ result: GraphClusterResult, rowCount: Int) async throws -> AnalysisChartData {
            calls += 1
            return try await AnalysisChartProjection().project(result, rowCount: rowCount)
        }
    }

    private struct RejectingProjection: AnalysisChartProjecting {
        func project(_ result: GraphClusterResult, rowCount: Int) async throws -> AnalysisChartData {
            throw AnalysisChartProjection.Failure.invalidResult
        }
    }
}
