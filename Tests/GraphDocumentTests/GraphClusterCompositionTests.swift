import XCTest
import simd
@testable import DatabaseStudioUI

@MainActor
final class GraphClusterCompositionTests: XCTestCase {
    private func populations() -> GraphDocument {
        GraphDocument(nodes: (0..<8).map { GraphNode(id: "n\($0)", label: "Node \($0)", role: .instance,
                                                   metadata: ["Category": $0 < 4 ? "A" : "B", "Common": "shared"]) }, edges: [])
    }

    private var categories: GraphClusterConfiguration {
        var c = GraphClusterConfiguration(); c.clusterCount = 2; c.metadataKeys = ["Category", "Common"]; return c
    }

    func testRoleLayersLiftTheSameProjectionWithoutInventingTopology() async throws {
        var document = populations()
        document.nodes.append(GraphNode(id: "type", label: "Type", role: .type))
        document.edges = (0..<8).map { GraphEdge(id: "e\($0)", sourceID: "n\($0)", targetID: "type", label: "instance of", edgeKind: .instanceOf) }
        let result = try await GraphFeatureAnalyzer().analyze(document: document, configuration: categories)
        let layout = try GraphSpatialLayout.layered(document: document, result: result)
        XCTAssertEqual(layout.layers.map(\.role), [.instance, .type])
        XCTAssertEqual(layout.layers.map(\.count), [8, 1])
        XCTAssertGreaterThan(layout.layers[0].height, layout.layers[1].height)
        XCTAssertEqual(Set(layout.nodeIDs), Set(document.nodes.map(\.id)))
        for node in document.nodes {
            let point = try XCTUnwrap(layout.positions[node.id]), xy = try XCTUnwrap(result.positions[node.id])
            XCTAssertEqual(point.x, Float(xy.x)); XCTAssertEqual(point.z, Float(xy.y))
            XCTAssertEqual(point.y, try XCTUnwrap(layout.layers.first { $0.role == node.role }).height)
        }
        var duplicate = document; duplicate.edges.append(document.edges[0])
        XCTAssertThrowsError(try GraphSpatialLayout.layered(document: duplicate, result: result))
        var incompletePositions = result.positions; incompletePositions.removeValue(forKey: "type")
        let missing = GraphClusterResult(configuration: result.configuration, clusters: result.clusters, membership: result.membership,
                                         positions: incompletePositions, unpositionedIDs: result.unpositionedIDs, unassignedIDs: result.unassignedIDs,
                                         featureCount: result.featureCount, retainedVariance: result.retainedVariance, iterations: result.iterations)
        XCTAssertThrowsError(try GraphSpatialLayout.layered(document: document, result: missing))
    }

    func testLayerSceneEmphasizesOriginalEdgesWithoutRebuildingTopology() async throws {
        var document = populations()
        document.nodes.append(GraphNode(id: "type", label: "Type", role: .type))
        document.edges = (0..<8).map { GraphEdge(id: "e\($0)", sourceID: "n\($0)", targetID: "type", label: "instance of", edgeKind: .instanceOf) }
        let result = try await GraphFeatureAnalyzer().analyze(document: document, configuration: categories)
        let layout = try GraphSpatialLayout.layered(document: document, result: result), size = CGSize(width: 900, height: 600)
        var camera = GraphSpatialCamera()
        let bounds = layout.bounds(for: document.nodes)
        camera.fit(center: bounds.center, radius: bounds.radius, size: size)
        let scene = GraphSpatialScene()
        scene.update(layout: layout, revision: 1, edges: document.edges)
        scene.project(camera: camera, layout: layout, revision: 1, nodes: document.nodes, selectedID: nil, size: size)
        XCTAssertTrue(scene.emphasizedPath.isEmpty)
        scene.project(camera: camera, layout: layout, revision: 1, nodes: document.nodes, selectedID: nil, size: size, emphasizedIDs: ["n0", "n1", "n2", "n3"])
        XCTAssertFalse(scene.emphasizedPath.isEmpty); XCTAssertFalse(scene.normalPath.isEmpty)
        XCTAssertEqual(scene.projectedEdgeCount, 8)
        XCTAssertTrue(scene.edgeLabels.isEmpty)
        scene.project(camera: camera, layout: layout, revision: 2, nodes: document.nodes, selectedID: "n0", size: size, emphasizedIDs: ["n0", "n1", "n2", "n3"])
        XCTAssertEqual(scene.edgeLabels.count, 1)
        XCTAssertEqual(scene.topologyBuildCount, 1)
        let type = try XCTUnwrap(scene.glyphs.first { $0.node.id == "type" })
        XCTAssertEqual(scene.hit(at: type.point), "type")
    }

    func testProjectionSwitchAndConfigurationRefreshPreserveSharedGraphState() async throws {
        let state = GraphViewState(document: populations(), showsAllNodes: true)
        state.queryText = "SELECT ?s WHERE { ?s ?p ?o } LIMIT 5"
        state.queryResultColumns = ["s"]
        state.queryResults = [QueryResultRow(bindings: ["s": "n0"])]
        state.clusterSession.configuration = categories
        state.usesFeatureClusters = true
        await state.clusterSession.prepare(document: state.document)
        let result = try XCTUnwrap(state.clusterSession.result)
        state.clusterSession.selectedCluster = 0; state.selectNode("n0")
        state.isSpatial = true
        await state.prepareSpatialLayout()
        let layout = try XCTUnwrap(state.spatialLayout)
        state.moveSpatialNode("n0", screen: .zero, planePoint: .zero)
        XCTAssertEqual(state.spatialLayout?.positions, layout.positions)
        state.isSpatial = false
        XCTAssertEqual(state.clusterSession.result?.positions, result.positions)
        XCTAssertEqual(state.selectedNodeID, "n0")
        XCTAssertEqual(state.clusterSession.selectedCluster, 0)
        XCTAssertEqual(state.queryText, "SELECT ?s WHERE { ?s ?p ?o } LIMIT 5")
        XCTAssertEqual(state.queryResultColumns, ["s"]); XCTAssertEqual(state.queryResults.count, 1)
        state.isSpatial = true; state.clusterSession.configuration.clusterCount = 3
        await state.prepareSpatialLayout()
        XCTAssertEqual(state.clusterSession.result?.configuration.clusterCount, 3)
        XCTAssertNotNil(state.spatialLayout); XCTAssertNil(state.spatialFailureMessage)
        state.document = GraphDocument()
        XCTAssertNil(state.clusterSession.result); XCTAssertNil(state.spatialLayout)
        await state.prepareSpatialLayout()
        XCTAssertNotNil(state.spatialFailureMessage)
        state.usesFeatureClusters = false
        XCTAssertNil(state.spatialLayout)
        XCTAssertNotNil(state.spatialUnavailableReason)
    }

}
