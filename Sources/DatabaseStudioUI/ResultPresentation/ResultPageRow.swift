import DatabaseKit
import DatabaseWire

/// Retains canonical field backing while keeping identity independent of display order.
struct ResultPageRow: Identifiable {
    let id: Int
    let values: [FieldValue]
    let canonical: DatabaseWire.QueryRow?

    init(index: Int, row: DatabaseWire.QueryRow) {
        id = index
        values = row.values
        canonical = row
    }

    init(index: Int, quad: RDFQuad) {
        id = index
        // RDF cells materialize once at this presentation boundary, never during sorting.
        values = [.rdfTerm(quad.subject.term), .rdfTerm(.iri(quad.predicate.iri)),
                  .rdfTerm(quad.object), quad.graph.map { .rdfTerm($0.term) } ?? .null]
        canonical = nil
    }
}
