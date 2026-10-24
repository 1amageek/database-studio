import DatabaseKit
import DatabaseWire

/// Retains canonical field backing while keeping identity independent of display order.
struct ResultPageRow: Identifiable {
    let id: Int
    let values: [DatabaseKit.QueryValue]
    let canonical: DatabaseKit.QueryRow?

    init(index: Int, row: DatabaseKit.QueryRow) {
        id = index
        values = row.values
        canonical = row
    }

    init(index: Int, quad: RDFQuad) {
        id = index
        // RDF cells materialize once at this presentation boundary, never during sorting.
        values = [.primitive(.rdfTerm(quad.subject.term)), .primitive(.rdfTerm(.iri(quad.predicate.iri))),
                  .primitive(.rdfTerm(quad.object)), quad.graph.map { .primitive(.rdfTerm($0.term)) } ?? .primitive(.null)]
        canonical = nil
    }
}
