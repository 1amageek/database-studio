import Testing
import DatabaseStudioCore

@Test func testIndexKindIdentifier() async throws {
    #expect(IndexKindIdentifier.scalar.subspaceStructure == .flat)
    #expect(IndexKindIdentifier.vector.subspaceStructure == .hierarchical)
    #expect(IndexKindIdentifier.count.subspaceStructure == .aggregation)
}

@Test func testIndexState() async throws {
    #expect(IndexState.readable.isUsable == true)
    #expect(IndexState.writeOnly.isUsable == false)
    #expect(IndexState.disabled.isUsable == false)
}
