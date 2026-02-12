import Foundation

/// SPARQL パース時のエラー
enum SPARQLParseError: Error, Sendable, LocalizedError {
    case unexpectedToken(expected: String, found: String, position: Int)
    case unexpectedEndOfInput(expected: String)
    case unsupportedFeature(String)
    case invalidIRI(String)
    case invalidLiteral(String)
    case undefinedPrefix(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedToken(let expected, let found, let position):
            return "Syntax error at token \(position): expected \(expected), found '\(found)'"
        case .unexpectedEndOfInput(let expected):
            return "Unexpected end of query: expected \(expected)"
        case .unsupportedFeature(let feature):
            return "Unsupported SPARQL feature: \(feature)"
        case .invalidIRI(let iri):
            return "Invalid IRI: \(iri)"
        case .invalidLiteral(let lit):
            return "Invalid literal: \(lit)"
        case .undefinedPrefix(let prefix):
            return "Undefined prefix: \(prefix):"
        }
    }
}
