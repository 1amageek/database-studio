/// SPARQL レキサートークン
enum SPARQLToken: Equatable, Sendable {

    // MARK: - Keywords

    case select
    case distinct
    case where_
    case limit
    case offset
    case orderBy
    case groupBy
    case having
    case asc
    case desc
    case filter
    case optional_
    case union
    case minus_
    case bind
    case as_
    case prefix_

    // Aggregate keywords
    case count
    case sum
    case avg
    case fnMin
    case fnMax
    case separator

    // Built-in functions
    case bound
    case isIRI
    case isLiteral
    case isBlank
    case str
    case lang
    case datatype
    case regex

    // MARK: - Punctuation

    case openBrace       // {
    case closeBrace      // }
    case openParen       // (
    case closeParen      // )
    case dot             // .
    case semicolon       // ;
    case comma           // ,
    case star            // *

    // MARK: - Operators

    case equal           // =
    case notEqual        // !=
    case lessThan        // <
    case greaterThan     // >
    case lessThanOrEqual // <=
    case greaterThanOrEqual // >=
    case and             // &&
    case or              // ||
    case bang            // !
    case plus            // +
    case minus__         // -
    case slash           // /
    case caretCaret      // ^^

    // MARK: - Values

    case variable(String)
    case iri(String)
    case prefixedName(String, String)
    case stringLiteral(String)
    case integerLiteral(Int64)
    case doubleLiteral(Double)
    case langTag(String)

    // MARK: - Special

    case a               // rdf:type shorthand
    case eof
}
