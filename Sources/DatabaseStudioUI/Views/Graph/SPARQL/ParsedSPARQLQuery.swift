/// パースされた SPARQL SELECT クエリ
struct ParsedSPARQLQuery: Sendable {
    var projection: ParsedProjection
    var wherePattern: ParsedGraphPattern
    var groupBy: [ParsedFilterExpr]?
    var having: ParsedFilterExpr?
    var orderBy: [ParsedOrderKey]?
    var limit: Int?
    var offset: Int?
    var prefixes: [String: String]
    var isDistinct: Bool
}

/// SELECT 射影
enum ParsedProjection: Sendable {
    case all
    case variables([String])
    case expressions([(ParsedFilterExpr, String)])
}

/// グラフパターン
indirect enum ParsedGraphPattern: Sendable {
    case bgp([ParsedTriplePattern])
    case join(ParsedGraphPattern, ParsedGraphPattern)
    case optional_(ParsedGraphPattern, ParsedGraphPattern)
    case union(ParsedGraphPattern, ParsedGraphPattern)
    case minus(ParsedGraphPattern, ParsedGraphPattern)
    case filter(ParsedGraphPattern, ParsedFilterExpr)
    case bind(ParsedGraphPattern, variable: String, expression: ParsedFilterExpr)
}

/// トリプルパターン
struct ParsedTriplePattern: Sendable {
    var subject: ParsedTerm
    var predicate: ParsedTerm
    var object: ParsedTerm
}

/// RDF 項
enum ParsedTerm: Sendable, Equatable {
    case variable(String)
    case iri(String)
    case prefixedName(prefix: String, local: String)
    case stringLiteral(String)
    case typedLiteral(value: String, datatype: String)
    case langLiteral(value: String, lang: String)
    case integerLiteral(Int64)
    case doubleLiteral(Double)
}

/// フィルター式 / 一般式
indirect enum ParsedFilterExpr: Sendable {
    // 比較
    case equal(ParsedFilterExpr, ParsedFilterExpr)
    case notEqual(ParsedFilterExpr, ParsedFilterExpr)
    case lessThan(ParsedFilterExpr, ParsedFilterExpr)
    case greaterThan(ParsedFilterExpr, ParsedFilterExpr)
    case lessThanOrEqual(ParsedFilterExpr, ParsedFilterExpr)
    case greaterThanOrEqual(ParsedFilterExpr, ParsedFilterExpr)

    // 論理
    case and(ParsedFilterExpr, ParsedFilterExpr)
    case or(ParsedFilterExpr, ParsedFilterExpr)
    case not(ParsedFilterExpr)

    // 算術
    case add(ParsedFilterExpr, ParsedFilterExpr)
    case subtract(ParsedFilterExpr, ParsedFilterExpr)
    case multiply(ParsedFilterExpr, ParsedFilterExpr)
    case divide(ParsedFilterExpr, ParsedFilterExpr)

    // 項
    case term(ParsedTerm)

    // 組み込み関数
    case bound(String)
    case isIRI(ParsedFilterExpr)
    case isLiteral(ParsedFilterExpr)
    case str(ParsedFilterExpr)
    case lang(ParsedFilterExpr)
    case regex(ParsedFilterExpr, pattern: String, flags: String?)

    // 集計
    case aggregate(ParsedAggregate)
}

/// 集計関数
enum ParsedAggregate: Sendable {
    case count(ParsedFilterExpr?, distinct: Bool)
    case sum(ParsedFilterExpr, distinct: Bool)
    case avg(ParsedFilterExpr, distinct: Bool)
    case min(ParsedFilterExpr)
    case max(ParsedFilterExpr)
}

/// ORDER BY キー
struct ParsedOrderKey: Sendable {
    var expression: ParsedFilterExpr
    var ascending: Bool
}
