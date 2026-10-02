import XCTest
import simd
import RealityKit
@testable import DatabaseStudioUI

@MainActor
final class SpatialGraphTests: XCTestCase {
    private func network(_ count: Int = 8) -> GraphDocument {
        let nodes = (0..<count).map { GraphNode(id: "node-\($0)", label: "Node \($0)", role: .instance) }
        let edges = (0..<max(0, count - 1)).map {
            GraphEdge(id: "edge-\($0)", sourceID: nodes[$0].id, targetID: nodes[($0 + 1) % count].id, label: "related")
        }
        return GraphDocument(nodes: nodes, edges: edges)
    }

    func testNetworkIsDeterministicAndPreservesTopologyWithoutRoleLayers() async throws {
        var document = network()
        document.edges.append(GraphEdge(id: "cycle", sourceID: "node-6", targetID: "node-0", label: "returns"))
        document.edges.append(GraphEdge(id: "parallel", sourceID: "node-0", targetID: "node-1", label: "alsoRelated"))
        document.edges.append(GraphEdge(id: "self", sourceID: "node-1", targetID: "node-1", label: "self"))
        document.nodes.append(GraphNode(id: "isolated", label: "Isolated", role: .instance))
        let original = document
        let layout = try await GraphSpatialLayout.compute(document: document)
        document.nodes.reverse()
        document.edges.reverse()
        for index in document.nodes.indices { document.nodes[index].role = .type }
        let reordered = try await GraphSpatialLayout.compute(document: document)
        XCTAssertEqual(layout.positions, reordered.positions)
        XCTAssertEqual(Set(layout.nodeIDs), Set(original.nodes.map(\.id)))
        XCTAssertGreaterThan(Set(layout.positions.values.map(\.y)).count, 1)
        XCTAssertTrue(layout.positions.values.allSatisfy(GraphSpatialLayout.finite))
        XCTAssertEqual(original.edges.count, 10)
        let empty = try await GraphSpatialLayout.compute(document: GraphDocument())
        XCTAssertEqual(empty.positions.count, 0)
    }

    func testAdmissionRejectsCapacityDuplicateIdentityMissingEndpointAndNonfiniteSeeds() async {
        var duplicateNode = network(); duplicateNode.nodes.append(duplicateNode.nodes[0])
        var duplicateEdge = network(); duplicateEdge.edges.append(duplicateEdge.edges[0])
        var missing = network(); missing.edges[0] = GraphEdge(id: "missing", sourceID: "absent", targetID: "node-1", label: "related")
        var excessEdges = network(2)
        excessEdges.edges = (0...GraphSpatialLayout.maximumEdges).map { GraphEdge(id: "edge-\($0)", sourceID: "node-0", targetID: "node-1", label: "related") }
        let documents = [network(GraphSpatialLayout.maximumNodes + 1), excessEdges, duplicateNode, duplicateEdge, missing]
        for document in documents {
            do { _ = try await GraphSpatialLayout.compute(document: document); XCTFail("Invalid graph admitted") }
            catch is GraphSpatialLayout.Failure { }
            catch { XCTFail("Unexpected failure: \(error)") }
        }
        do {
            _ = try await GraphSpatialLayout.compute(document: network(), initialPositions: ["node-0": SIMD3(.nan, 0, 0)])
            XCTFail("Nonfinite seed admitted")
        } catch GraphSpatialLayout.Failure.invalidPosition { }
        catch { XCTFail("Unexpected failure: \(error)") }
    }

    func testCancelledLayoutCannotReturnSuccessfulCoordinates() async {
        let task = Task { try await GraphSpatialLayout.compute(document: network(512)) }
        await Task.yield()
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled layout succeeded") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected failure: \(error)") }
    }

    func testCameraProjectionAndCameraFacingDragAfterOrbitPanAndZoom() throws {
        var camera = GraphSpatialCamera()
        let size = CGSize(width: 900, height: 600)
        camera.fit(radius: 5, size: size)
        camera.orbit(dx: 70, dy: 20)
        camera.pan(dx: 12, dy: 5, height: size.height)
        camera.zoom(0.2)
        let world = SIMD3<Float>(1, 0.7, -1)
        let screen = try XCTUnwrap(camera.project(world, size: size))
        let restored = try XCTUnwrap(camera.point(onPlaneThrough: world, screen: screen.point, size: size))
        XCTAssertLessThan(simd_distance(world, restored), 0.0001)
        let moved = try XCTUnwrap(camera.point(onPlaneThrough: world, screen: CGPoint(x: screen.point.x + 20, y: screen.point.y), size: size))
        XCTAssertEqual(simd_dot(moved - world, camera.backward), 0, accuracy: 0.0001)
        XCTAssertNil(camera.project(camera.eye + camera.backward, size: size))
        XCTAssertNil(camera.project(SIMD3(.nan, 0, 0), size: size))
        XCTAssertNil(camera.point(onPlaneThrough: world, screen: .zero, size: .zero))
    }

    func testThreeFingerTranslationTwistAndContactReset() throws {
        var input = ThreeFingerRotation()
        let initial: [AnyHashable: CGPoint] = [0: CGPoint(x: -10, y: -10),
                                               1: CGPoint(x: 10, y: -10), 2: CGPoint(x: 0, y: 20)]
        XCTAssertNil(input.update(initial))
        let moved = initial.mapValues { CGPoint(x: $0.x + 12, y: $0.y - 8) }
        let delta = try XCTUnwrap(input.update(moved))
        XCTAssertEqual(delta.translation.width, 12, accuracy: 0.0001)
        XCTAssertEqual(delta.translation.height, -8, accuracy: 0.0001)
        XCTAssertEqual(delta.roll, 0, accuracy: 0.0001)
        let twisted = moved.mapValues { CGPoint(x: 12 - ($0.y + 8), y: -8 + ($0.x - 12)) }
        let twist = try XCTUnwrap(input.update(twisted))
        XCTAssertEqual(twist.roll, -.pi / 2, accuracy: 0.0001)
        XCTAssertEqual(twist.translation.width, 0, accuracy: 0.0001)
        XCTAssertEqual(twist.translation.height, 0, accuracy: 0.0001)
        XCTAssertNil(input.update([0: .zero, 1: .zero]))
        XCTAssertNil(input.update(initial))
        XCTAssertNil(input.update([0: .zero, 1: .zero, 2: .zero, 3: .zero]))
        XCTAssertNil(input.update(initial))
        XCTAssertNil(input.update([0: .zero, 1: .zero, 3: .zero]))
        XCTAssertNil(input.update(initial))
        input.reset()
        XCTAssertNil(input.update(moved))
        XCTAssertNil(input.update([0: CGPoint(x: CGFloat.nan, y: 0), 1: .zero, 2: .zero]))
        XCTAssertNil(input.update(initial))
    }

    func testFullCameraRotationAndRollShareNativeProjectionBasis() async throws {
        var camera = GraphSpatialCamera(yaw: 0, pitch: 0, distance: 10)
        let initial = camera
        camera.orbit(dx: 0, dy: CGFloat(Float.pi / 0.006))
        XCTAssertLessThan(simd_distance(camera.backward, SIMD3(0, 0, -1)), 0.0001)
        camera.orbit(dx: 0, dy: CGFloat(Float.pi / 0.006))
        XCTAssertLessThan(simd_distance(camera.backward, initial.backward), 0.0001)
        camera.orbit(dx: 0, dy: 0, roll: .pi / 2)
        XCTAssertLessThan(simd_distance(camera.right, SIMD3(0, 1, 0)), 0.0001)
        let size = CGSize(width: 900, height: 600)
        let projected = try XCTUnwrap(camera.project(SIMD3(1, 0, 0), size: size))
        XCTAssertEqual(projected.point.x, 450, accuracy: 0.0001)
        XCTAssertGreaterThan(projected.point.y, 300)
        let restored = try XCTUnwrap(camera.point(onPlaneThrough: SIMD3(1, 0, 0), screen: projected.point, size: size))
        XCTAssertLessThan(simd_distance(restored, SIMD3(1, 0, 0)), 0.0001)
        for _ in 0..<1000 { camera.orbit(dx: 3, dy: 5, roll: 0.01) }
        XCTAssertEqual(simd_length(camera.orientation.vector), 1, accuracy: 0.0001)
        let unchanged = camera
        camera.orbit(dx: .nan, dy: 0)
        XCTAssertEqual(camera, unchanged)
        let document = network(3)
        let layout = try await GraphSpatialLayout.compute(document: document)
        let scene = GraphSpatialScene()
        try scene.update(camera: camera, layout: layout, revision: 1, edges: document.edges, selectedID: nil, dark: false)
        let native = try XCTUnwrap(scene.root.children.compactMap { $0 as? PerspectiveCamera }.first)
        XCTAssertLessThan(simd_distance(native.position, camera.eye), 0.0001)
        for axis in [SIMD3<Float>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)] {
            XCTAssertLessThan(simd_distance(native.orientation.act(axis), camera.orientation.act(axis)), 0.0001)
        }
        scene.project(camera: camera, layout: layout, revision: 1, nodes: document.nodes, selectedID: nil, size: size)
        for glyph in scene.glyphs { XCTAssertEqual(scene.hit(at: glyph.point), glyph.node.id) }
        camera.orbit(dx: 10, dy: -10, roll: 0.3)
        try scene.update(camera: camera, layout: layout, revision: 1, edges: document.edges, selectedID: nil, dark: false)
        XCTAssertEqual(scene.geometryBuildCount, 1)

    }

    func testResearchedDatasetProvenanceFailuresAndFullVisibility() async throws {
        let document = try AutomotiveGraphSnapshot.load()
        XCTAssertEqual(document.nodes.count, 1000)
        XCTAssertEqual(document.edges.count, 2584)
        XCTAssertEqual(Set(document.nodes.map(\.id)).count, 1000)
        XCTAssertEqual(Set(document.edges.map(\.id)).count, 2584)
        XCTAssertTrue(document.nodes.allSatisfy { $0.metadata["License"] == "CC0-1.0" && $0.metadata["Source URL"]?.hasPrefix("https://www.wikidata.org/wiki/Q") == true })
        XCTAssertTrue(document.edges.allSatisfy { $0.ontologyProperty?.hasPrefix("http://www.wikidata.org/prop/direct/P") == true })
        XCTAssertTrue(document.edges.contains { $0.label == "manufacturer" })
        XCTAssertTrue(document.edges.contains { $0.label == "owned by" })
        XCTAssertEqual(document.nodes.first { $0.id == "http://www.wikidata.org/entity/Q3231690" }?.role, .type)
        let state = GraphViewState(document: document, showsAllNodes: true)
        XCTAssertEqual(state.visibleNodes.count, 1000)
        XCTAssertEqual(state.visibleEdges.count, 2584)
        XCTAssertFalse(state.isSpatial)
        XCTAssertFalse(state.isBackboneActive)
        XCTAssertNil(state.spatialUnavailableReason)
        let typeEdge = try XCTUnwrap(document.edges.first { $0.edgeKind == .instanceOf })
        XCTAssertTrue(state.nodeTypeMap[typeEdge.sourceID]?.contains(typeEdge.targetID) == true)
        let queryable = SPARQLDataset(document: document)
        XCTAssertEqual(queryable.match(subject: nil, predicate: "http://www.wikidata.org/prop/direct/P176", object: nil).count, 833)
        XCTAssertEqual(GraphSpatialLayout.iterationLimit(nodeCount: 1000), 31)
        XCTAssertEqual(GraphSpatialLayout.iterationLimit(nodeCount: 512), 120)
        XCTAssertLessThanOrEqual(1000 * 999 / 2 * GraphSpatialLayout.iterationLimit(nodeCount: 1000), GraphSpatialLayout.maximumRepulsionPairs)
        let window = GraphWindowState()
        window.showExample()
        XCTAssertTrue(window.showsAllNodes)
        XCTAssertNil(window.document)
        let load = try XCTUnwrap(window.loadDocument)
        window.loadDocument = { GraphDocument() }
        XCTAssertFalse(window.showsAllNodes)
        let loaded = try await load()
        XCTAssertEqual(loaded?.nodes.count, 1000)
        XCTAssertThrowsError(try AutomotiveGraphSnapshot.decode(Data("{}".utf8)))
        let first = try XCTUnwrap(document.nodes.first)
        let rows = try document.edges.map { [$0.sourceID, try XCTUnwrap($0.ontologyProperty), $0.targetID] }
        let properties = try Dictionary(document.edges.map { (try XCTUnwrap($0.ontologyProperty), $0.label) }, uniquingKeysWith: { first, _ in first })
        let payload: [String: Any] = ["source": "Wikidata", "sourceURL": "https://www.wikidata.org/", "license": "CC0-1.0",
                                     "retrievedAt": try XCTUnwrap(first.metadata["Retrieved"]),
                                     "selection": try XCTUnwrap(first.metadata["Sampling"]),
                                     "labels": Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0.label) }),
                                     "triples": rows, "propertyLabels": properties]
        XCTAssertEqual(try AutomotiveGraphSnapshot.decode(JSONSerialization.data(withJSONObject: payload)), document)
        var malformed = payload; malformed["triples"] = [["missing"]] + rows
        var duplicated = payload; duplicated["triples"] = rows + [rows[0]]
        var missingEndpoint = payload; var changed = rows; changed[0][2] = "http://www.wikidata.org/entity/Q0"; missingEndpoint["triples"] = changed
        var wrongCount = payload; var labels = try XCTUnwrap(payload["labels"] as? [String: String]); labels.removeValue(forKey: first.id); wrongCount["labels"] = labels
        let degree = GraphMetricsComputer.compute(document: document).degree
        let leaf = try XCTUnwrap(document.nodes.first { degree[$0.id] == 1 })
        var disconnected = payload; disconnected["triples"] = rows.filter { $0[0] != leaf.id && $0[2] != leaf.id }
        for invalid in [malformed, duplicated, missingEndpoint, wrongCount, disconnected] {
            XCTAssertThrowsError(try AutomotiveGraphSnapshot.decode(JSONSerialization.data(withJSONObject: invalid))) { error in
                XCTAssertTrue(error is AutomotiveGraphSnapshot.Failure)
            }
        }
    }

    func testThousandResearchedEntitiesRenderWithinRetainedWorkBudget() async throws {
        let document = try AutomotiveGraphSnapshot.load()
        let clock = ContinuousClock(), start = clock.now
        let layout = try await GraphSpatialLayout.compute(document: document)
        let nativeStart = clock.now
        XCTAssertEqual(layout.positions.count, 1000)
        XCTAssertTrue(layout.positions.values.allSatisfy(GraphSpatialLayout.finite))
        let size = CGSize(width: 1600, height: 1000)
        let bounds = layout.bounds(for: document.nodes)
        var camera = GraphSpatialCamera()
        camera.fit(center: bounds.center, radius: bounds.radius, size: size)
        let scene = GraphSpatialScene()
        try scene.update(camera: camera, layout: layout, revision: 1, edges: document.edges, selectedID: nil, dark: true)
        let projectionStart = clock.now
        scene.project(camera: camera, layout: layout, revision: 1, nodes: document.nodes, selectedID: nil, size: size)
        XCTAssertEqual(scene.glyphs.count, 1000)
        let nearest = try XCTUnwrap(scene.glyphs.last)
        XCTAssertEqual(scene.hit(at: nearest.point), nearest.node.id)
        camera.orbit(dx: 90, dy: 120, roll: 0.2)
        try scene.update(camera: camera, layout: layout, revision: 1, edges: document.edges, selectedID: nil, dark: true)
        XCTAssertEqual(scene.geometryBuildCount, 1)
        print("Researched dataset: 1000 entities / 2584 relationships; layout \(start.duration(to: nativeStart)); native geometry \(nativeStart.duration(to: projectionStart)); projection/checks \(projectionStart.duration(to: clock.now))")
    }

    func testNodeDragChangesOnlyPresentationOnCameraFacingPlane() async throws {
        let document = network()
        let state = GraphViewState(document: document)
        state.spatialViewport = CGSize(width: 900, height: 600)
        state.isSpatial = true
        await state.prepareSpatialLayout()
        let layout = try XCTUnwrap(state.spatialLayout)
        let initial = try XCTUnwrap(layout.positions["node-0"])
        let point = try XCTUnwrap(state.spatialCamera.project(initial, size: state.spatialViewport)).point
        state.moveSpatialNode("node-0", screen: CGPoint(x: point.x + 20, y: point.y), planePoint: initial)
        let moved = try XCTUnwrap(state.spatialLayout?.positions["node-0"])
        XCTAssertEqual(simd_dot(moved - initial, state.spatialCamera.backward), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(simd_distance(initial, moved), 0)
        XCTAssertEqual(state.document.edges, document.edges)
        state.isSpatial = false
    }

    func testProjectionSwitchPreservesVisibilityQuerySelectionAndBothCameras() async throws {
        let state = GraphViewState(document: network())
        state.selectNode("node-0")
        state.showQueryPanel = true
        state.queryText = "SELECT ?s WHERE { ?s ?p ?o }"
        state.queryResults = [QueryResultRow(bindings: ["s": "node-0"])]
        state.cameraScale = 0.75
        state.cameraOffset = CGSize(width: 12, height: 30)
        let visible = state.visibleNodeIDs
        let edges = state.visibleEdges
        state.spatialViewport = CGSize(width: 900, height: 600)
        state.isSpatial = true
        await state.prepareSpatialLayout()
        let positions = try XCTUnwrap(state.spatialLayout).positions
        state.spatialCamera.orbit(dx: 40, dy: 20)
        let camera = state.spatialCamera
        state.isSpatial = false
        state.isSpatial = true
        await state.prepareSpatialLayout()
        XCTAssertEqual(state.selectedNodeID, "node-0")
        XCTAssertEqual(state.visibleNodeIDs, visible)
        XCTAssertEqual(state.visibleEdges, edges)
        XCTAssertTrue(state.showQueryPanel)
        XCTAssertEqual(state.queryResults.first?.bindings["s"], "node-0")
        XCTAssertEqual(state.queryText, "SELECT ?s WHERE { ?s ?p ?o }")
        XCTAssertEqual(state.spatialCamera, camera)
        XCTAssertEqual(state.spatialLayout?.positions, positions)
        XCTAssertEqual(state.cameraScale, 0.75)
        XCTAssertEqual(state.cameraOffset, CGSize(width: 12, height: 30))
        state.isSpatial = false
    }

    func testSourceReplacementAndLeaving3DRejectStaleLayoutPublication() async throws {
        let state = GraphViewState(document: network(512))
        state.isSpatial = true
        let first = Task { await state.prepareSpatialLayout() }
        while !state.isSpatialLoading { await Task.yield() }
        state.updateDocument(network(3))
        await state.prepareSpatialLayout()
        await first.value
        XCTAssertEqual(state.spatialLayout?.positions.count, 3)
        XCTAssertFalse(state.isSpatialLoading)
        state.updateDocument(network(512))
        let next = Task { await state.prepareSpatialLayout() }
        while !state.isSpatialLoading { await Task.yield() }
        state.isSpatial = false
        await next.value
        XCTAssertNil(state.spatialLayout)
        XCTAssertFalse(state.isSpatialLoading)
    }

    func testHierarchyAndTimelineRemain2DAndEqualCountUpdateInvalidatesLayout() async throws {
        var hierarchy = network()
        for index in hierarchy.edges.indices { hierarchy.edges[index].edgeKind = .subClassOf }
        let state = GraphViewState(document: hierarchy)
        XCTAssertFalse(state.isSpatial)
        XCTAssertNotNil(state.spatialUnavailableReason)
        state.updateDocument(network())
        XCTAssertNil(state.spatialUnavailableReason)
        state.timelineOrientation = .horizontal
        XCTAssertNotNil(state.spatialUnavailableReason)
        state.timelineOrientation = .off
        state.isSpatial = true
        await state.prepareSpatialLayout()
        XCTAssertNotNil(state.spatialLayout)
        var changed = network(); changed.nodes[0].label = "Changed without count changes"
        state.updateDocument(changed)
        XCTAssertNil(state.spatialLayout)
        await state.prepareSpatialLayout()
        XCTAssertEqual(state.document.nodes[0].label, changed.nodes[0].label)
        state.isSpatial = false
    }

    func testNativeGeometryIsRetainedDuringCameraMotionAndPickingMatchesVisibleGlyphs() async throws {
        let document = network(3)
        var layout = try await GraphSpatialLayout.compute(document: document)
        try layout.move("node-0", to: SIMD3(0, 0, 1))
        try layout.move("node-1", to: SIMD3(0, 0, -1))
        try layout.move("node-2", to: SIMD3(2, 0, 0))
        var camera = GraphSpatialCamera(yaw: 0, pitch: 0, distance: 10)
        let scene = GraphSpatialScene()
        let size = CGSize(width: 900, height: 600)
        try scene.update(camera: camera, layout: layout, revision: 1, edges: document.edges, selectedID: nil, dark: true)
        scene.project(camera: camera, layout: layout, revision: 1, nodes: document.nodes, selectedID: nil, size: size)
        XCTAssertEqual(scene.hit(at: CGPoint(x: 450, y: 300)), "node-0")
        XCTAssertNil(scene.hit(at: .zero))
        camera.orbit(dx: 100, dy: 10)
        try scene.update(camera: camera, layout: layout, revision: 1, edges: document.edges, selectedID: nil, dark: true)
        XCTAssertEqual(scene.geometryBuildCount, 1)
        scene.project(camera: camera, layout: layout, revision: 1, nodes: document.nodes, selectedID: nil, size: size)
        for glyph in scene.glyphs { XCTAssertEqual(scene.hit(at: glyph.point), glyph.node.id) }

        var admitted = network(2)
        admitted.edges = (0..<GraphSpatialLayout.maximumEdges).map {
            GraphEdge(id: "dense-\($0)", sourceID: "node-0", targetID: "node-1", label: "related")
        }
        let clock = ContinuousClock()
        let layoutStart = clock.now
        let bounded = try await GraphSpatialLayout.compute(document: admitted)
        let geometryStart = clock.now
        try scene.update(camera: camera, layout: bounded, revision: 2, edges: admitted.edges, selectedID: nil, dark: true)
        let projectionStart = clock.now
        scene.project(camera: camera, layout: bounded, revision: 2, nodes: admitted.nodes, selectedID: nil, size: size)
        let finish = clock.now
        camera.orbit(dx: 20, dy: 10)
        try scene.update(camera: camera, layout: bounded, revision: 2, edges: admitted.edges, selectedID: nil, dark: true)
        XCTAssertEqual(scene.geometryBuildCount, 2)
        XCTAssertEqual(bounded.positions.count, 2)
        print("Spatial geometry measurement: 2 nodes / 4096 parallel edges; layout \(layoutStart.duration(to: geometryStart)); native geometry \(geometryStart.duration(to: projectionStart)); projection \(projectionStart.duration(to: finish))")
    }

    func testSupersededQueryDoesNotPublish() async {
        let state = GraphViewState(document: GraphSampleData.rdfDocument)
        state.executeQuery()
        state.updateDocument(GraphDocument())
        await Task.yield()
        XCTAssertTrue(state.queryResults.isEmpty)
        XCTAssertFalse(state.isQueryExecuting)
    }
}
