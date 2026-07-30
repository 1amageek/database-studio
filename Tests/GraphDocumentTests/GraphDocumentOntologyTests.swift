import Testing
import Foundation
@testable import DatabaseStudioUI
import Graph

@Suite("GraphDocument Ontology Constructor")
struct GraphDocumentOntologyTests {

    // MARK: - Ontology Test Data

    private func makeOntology(
        classes: [OWLClass] = [],
        axioms: [OWLAxiom] = [],
        objectProperties: [OWLObjectProperty] = [],
        dataProperties: [OWLDataProperty] = []
    ) -> OWLOntology {
        OWLOntology(
            iri: "http://example.org/test",
            classes: classes,
            objectProperties: objectProperties,
            dataProperties: dataProperties,
            axioms: axioms
        )
    }

    // MARK: - クラス → ノード

    @Test("OWLClass becomes .type node with .ontology source")
    func classToTypeNode() {
        let ontology = makeOntology(classes: [
            OWLClass(iri: "http://example.org/Person", label: "Person"),
        ])
        let graphDocument = GraphDocument(ontology: ontology)

        let personNode = graphDocument.nodes.first { $0.id == "http://example.org/Person" }
        #expect(personNode != nil)
        #expect(personNode?.role == .type)
        #expect(personNode?.source == .ontology)
        #expect(personNode?.label == "Person")
        #expect(personNode?.ontologyClass == "http://example.org/Person")
    }

    // MARK: - subClassOf axiom → エッジ

    @Test("subClassOf axiom creates .subClassOf edge")
    func subClassOfAxiomEdge() {
        let ontology = makeOntology(
            classes: [
                OWLClass(iri: "http://example.org/Employee"),
                OWLClass(iri: "http://example.org/Person"),
            ],
            axioms: [
                .subClassOf(
                    sub: .named("http://example.org/Employee"),
                    sup: .named("http://example.org/Person")
                ),
            ]
        )
        let graphDocument = GraphDocument(ontology: ontology)

        let edge = graphDocument.edges.first { $0.edgeKind == .subClassOf }
        #expect(edge != nil)
        #expect(edge?.sourceID == "http://example.org/Employee")
        #expect(edge?.targetID == "http://example.org/Person")
        #expect(edge?.label == "subClassOf")
    }

    // MARK: - ObjectProperty → エッジ

    @Test("ObjectProperty creates .property edge from domain to range")
    func objectPropertyEdge() {
        let ontology = makeOntology(
            classes: [
                OWLClass(iri: "http://example.org/Person"),
                OWLClass(iri: "http://example.org/Department"),
            ],
            objectProperties: [
                OWLObjectProperty(
                    iri: "http://example.org/worksFor",
                    label: "works for",
                    domains: [.named("http://example.org/Person")],
                    ranges: [.named("http://example.org/Department")]
                ),
            ]
        )
        let graphDocument = GraphDocument(ontology: ontology)

        let edge = graphDocument.edges.first { $0.edgeKind == .property }
        #expect(edge != nil)
        #expect(edge?.sourceID == "http://example.org/Person")
        #expect(edge?.targetID == "http://example.org/Department")
        #expect(edge?.label == "works for")
        #expect(edge?.ontologyProperty == "http://example.org/worksFor")
    }

    // MARK: - DataProperty → metadata

    @Test("DataProperty is stored in domain node metadata with dp: prefix")
    func dataPropertyMetadata() {
        let ontology = makeOntology(
            classes: [
                OWLClass(iri: "http://example.org/Person"),
            ],
            dataProperties: [
                OWLDataProperty(
                    iri: "http://example.org/age",
                    label: "age",
                    domains: [.named("http://example.org/Person")],
                    ranges: [.datatype("xsd:integer")]
                ),
            ]
        )
        let graphDocument = GraphDocument(ontology: ontology)

        let person = graphDocument.nodes.first { $0.id == "http://example.org/Person" }
        #expect(person != nil)
        #expect(person?.metadata["dp:age"] != nil)
        // DataProperty はエッジにならない
        #expect(graphDocument.edges.isEmpty)
    }

    // MARK: - 参照整合性

    @Test("All edge endpoints reference existing nodes")
    func referentialIntegrity() {
        let ontology = makeOntology(
            classes: [
                OWLClass(iri: "http://example.org/A"),
                OWLClass(iri: "http://example.org/B"),
                OWLClass(iri: "http://example.org/C"),
            ],
            axioms: [
                .subClassOf(sub: .named("http://example.org/B"), sup: .named("http://example.org/A")),
            ],
            objectProperties: [
                OWLObjectProperty(
                    iri: "http://example.org/rel",
                    domains: [.named("http://example.org/A")],
                    ranges: [.named("http://example.org/C")]
                ),
            ]
        )
        let graphDocument = GraphDocument(ontology: ontology)
        let nodeIDs = Set(graphDocument.nodes.map(\.id))
        for edge in graphDocument.edges {
            #expect(nodeIDs.contains(edge.sourceID))
            #expect(nodeIDs.contains(edge.targetID))
        }
    }

    // MARK: - クラスラベルのフォールバック

    @Test("Class without label uses IRI local name")
    func classLabelFallback() {
        let ontology = makeOntology(classes: [
            OWLClass(iri: "http://example.org/onto#MyClass"),
        ])
        let graphDocument = GraphDocument(ontology: ontology)
        let node = graphDocument.nodes.first { $0.id == "http://example.org/onto#MyClass" }
        #expect(node?.label == "MyClass")
    }

    // MARK: - コメント metadata

    @Test("Class comment is stored in metadata")
    func classCommentMetadata() {
        let ontology = makeOntology(classes: [
            OWLClass(iri: "http://example.org/Person", comment: "A human being"),
        ])
        let graphDocument = GraphDocument(ontology: ontology)
        let node = graphDocument.nodes.first { $0.id == "http://example.org/Person" }
        #expect(node?.metadata["comment"] == "A human being")
    }

    // MARK: - axiom から暗黙ノード生成

    @Test("subClassOf axiom ensures nodes exist even without explicit OWLClass")
    func axiomEnsuresNodes() {
        let ontology = makeOntology(
            axioms: [
                .subClassOf(
                    sub: .named("http://example.org/Child"),
                    sup: .named("http://example.org/Parent")
                ),
            ]
        )
        let graphDocument = GraphDocument(ontology: ontology)
        #expect(graphDocument.nodes.contains { $0.id == "http://example.org/Child" })
        #expect(graphDocument.nodes.contains { $0.id == "http://example.org/Parent" })
        #expect(graphDocument.nodes.first { $0.id == "http://example.org/Child" }?.role == .type)
    }
}
