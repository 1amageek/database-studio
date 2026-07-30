import Testing
import Foundation
@testable import DatabaseStudioUI
import Graph

@Suite("GraphDocument RDF Constructor")
struct GraphDocumentRDFTests {

    // MARK: - 不変条件: ノード一意性 & エッジ参照整合性

    @Test("All edge endpoints reference existing nodes")
    func referentialIntegrity() throws {
        let triples = [
            RDFTripleData(subject: "ex:alice", predicate: "ex:knows", object: "ex:bob"),
            RDFTripleData(subject: "ex:alice", predicate: "rdf:type", object: "ex:Person"),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let nodeIDs = Set(graphDocument.nodes.map(\.id))
        for edge in graphDocument.edges {
            #expect(nodeIDs.contains(edge.sourceID))
            #expect(nodeIDs.contains(edge.targetID))
        }
    }

    @Test("Node IDs are unique")
    func nodeUniqueness() throws {
        let triples = [
            RDFTripleData(subject: "ex:alice", predicate: "ex:knows", object: "ex:bob"),
            RDFTripleData(subject: "ex:bob", predicate: "ex:knows", object: "ex:alice"),
            RDFTripleData(subject: "ex:alice", predicate: "rdf:type", object: "ex:Person"),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let ids = graphDocument.nodes.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - rdf:type 昇格契約

    @Test("rdf:type promotes object to .type role")
    func rdfTypePromotion() throws {
        let triples = [
            RDFTripleData(subject: "ex:alice", predicate: "rdf:type", object: "ex:Person"),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let personNode = graphDocument.nodes.first { $0.id == "ex:Person" }
        #expect(personNode != nil)
        #expect(personNode?.role == .type)
    }

    @Test("rdf:type sets ontologyClass on both subject and object")
    func rdfTypeSetsOntologyClass() throws {
        let triples = [
            RDFTripleData(subject: "ex:alice", predicate: "rdf:type", object: "ex:Person"),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let alice = graphDocument.nodes.first { $0.id == "ex:alice" }
        let person = graphDocument.nodes.first { $0.id == "ex:Person" }
        #expect(alice?.ontologyClass == "ex:Person")
        #expect(person?.ontologyClass == "ex:Person")
    }

    @Test("rdf:type creates .instanceOf edge")
    func rdfTypeEdgeKind() throws {
        let triples = [
            RDFTripleData(subject: "ex:alice", predicate: "rdf:type", object: "ex:Person"),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let typeEdge = graphDocument.edges.first { $0.label == "rdf:type" }
        #expect(typeEdge != nil)
        #expect(typeEdge?.edgeKind == .instanceOf)
        #expect(typeEdge?.sourceID == "ex:alice")
        #expect(typeEdge?.targetID == "ex:Person")
    }

    // MARK: - subClassOf 昇格契約

    @Test("subClassOf promotes both endpoints to .type")
    func subClassOfPromotion() throws {
        let triples = [
            RDFTripleData(subject: "ex:Employee", predicate: "rdfs:subClassOf", object: "ex:Person"),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let employee = graphDocument.nodes.first { $0.id == "ex:Employee" }
        let person = graphDocument.nodes.first { $0.id == "ex:Person" }
        #expect(employee?.role == .type)
        #expect(person?.role == .type)
    }

    @Test("subClassOf creates .subClassOf edge")
    func subClassOfEdgeKind() throws {
        let triples = [
            RDFTripleData(subject: "ex:Employee", predicate: "rdfs:subClassOf", object: "ex:Person"),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let edge = graphDocument.edges.first { $0.edgeKind == .subClassOf }
        #expect(edge != nil)
        #expect(edge?.sourceID == "ex:Employee")
        #expect(edge?.targetID == "ex:Person")
    }

    @Test("subClassOf detection is case-insensitive")
    func subClassOfCaseInsensitive() throws {
        let triples = [
            RDFTripleData(subject: "ex:Dog", predicate: "ex:SubClassOf", object: "ex:Animal"),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let edge = graphDocument.edges.first { $0.edgeKind == .subClassOf }
        #expect(edge != nil)
        #expect(graphDocument.nodes.first { $0.id == "ex:Dog" }?.role == .type)
        #expect(graphDocument.nodes.first { $0.id == "ex:Animal" }?.role == .type)
    }

    // MARK: - リテラル処理契約

    @Test("Quoted object values become metadata, not nodes")
    func literalToMetadata() throws {
        let triples = [
            RDFTripleData(subject: "ex:alice", predicate: "ex:name", object: "\"Alice\""),
        ]
        let graphDocument = try GraphDocument(triples: triples)

        // リテラルはノードにならない
        #expect(graphDocument.nodes.count == 1)
        #expect(graphDocument.nodes[0].id == "ex:alice")

        // metadata に格納される
        #expect(graphDocument.nodes[0].metadata["name"] == "Alice")
    }

    @Test("RDF literal parsing handles datatype and language tags")
    func literalParsing() throws {
        let triples = [
            RDFTripleData(subject: "ex:item", predicate: "ex:count", object: "\"42\"^^<http://www.w3.org/2001/XMLSchema#integer>"),
            RDFTripleData(subject: "ex:item", predicate: "ex:label", object: "\"Hello\"@en"),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let item = graphDocument.nodes.first { $0.id == "ex:item" }
        #expect(item != nil)
        #expect(item?.metadata["count"] == "42")
        #expect(item?.metadata["label"] == "Hello")
    }

    // MARK: - ノード重複排除

    @Test("Same IRI in multiple triples produces single node")
    func nodeDeduplication() throws {
        let triples = [
            RDFTripleData(subject: "ex:alice", predicate: "ex:knows", object: "ex:bob"),
            RDFTripleData(subject: "ex:alice", predicate: "ex:likes", object: "ex:carol"),
            RDFTripleData(subject: "ex:bob", predicate: "ex:knows", object: "ex:alice"),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let aliceNodes = graphDocument.nodes.filter { $0.id == "ex:alice" }
        #expect(aliceNodes.count == 1)
    }

    @Test("Node initially .instance can be promoted to .type by rdf:type")
    func lazyPromotion() throws {
        let triples = [
            // ex:Person は最初 object property で .instance として登場
            RDFTripleData(subject: "ex:alice", predicate: "ex:sees", object: "ex:Person"),
            // 後の rdf:type で .type に昇格
            RDFTripleData(subject: "ex:bob", predicate: "rdf:type", object: "ex:Person"),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let person = graphDocument.nodes.first { $0.id == "ex:Person" }
        #expect(person?.role == .type)
    }

    // MARK: - rdf:type の別表記

    @Test("Full IRI rdf:type is recognized")
    func fullIRIRdfType() throws {
        let triples = [
            RDFTripleData(
                subject: "ex:alice",
                predicate: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
                object: "ex:Person"
            ),
        ]
        let graphDocument = try GraphDocument(triples: triples)
        let edge = graphDocument.edges.first { $0.edgeKind == .instanceOf }
        #expect(edge != nil)
        #expect(graphDocument.nodes.first { $0.id == "ex:Person" }?.role == .type)
    }
}
