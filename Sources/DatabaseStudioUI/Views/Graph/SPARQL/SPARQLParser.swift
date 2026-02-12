/// SPARQL SELECT クエリの再帰下降パーサー
struct SPARQLParser: Sendable {
    private var tokens: [SPARQLToken]
    private var position: Int

    private init(tokens: [SPARQLToken]) {
        self.tokens = tokens
        self.position = 0
    }

    /// SPARQL テキストをパースして AST を返す
    static func parse(_ sparql: String) throws -> ParsedSPARQLQuery {
        var lexer = SPARQLLexer(input: sparql)
        let tokens = try lexer.tokenize()
        var parser = SPARQLParser(tokens: tokens)
        return try parser.parseQuery()
    }

    // MARK: - Query

    private mutating func parseQuery() throws -> ParsedSPARQLQuery {
        let prefixes = try parsePrefixDeclarations()

        try expect(.select)

        let isDistinct = consume(.distinct)

        let projection = try parseProjection()

        try expect(.where_)

        let pattern = try parseGroupGraphPattern()

        let groupBy = try parseGroupByClause()
        let having = try parseHavingClause()
        let orderBy = try parseOrderByClause()
        let (limit, offset) = parseLimitOffset()

        return ParsedSPARQLQuery(
            projection: projection,
            wherePattern: pattern,
            groupBy: groupBy,
            having: having,
            orderBy: orderBy,
            limit: limit,
            offset: offset,
            prefixes: prefixes,
            isDistinct: isDistinct
        )
    }

    // MARK: - PREFIX

    private mutating func parsePrefixDeclarations() throws -> [String: String] {
        var prefixes: [String: String] = [:]
        while peek() == .prefix_ {
            advance()
            // prefix name (prefixedName with empty local, or just the prefix part)
            let prefixName: String
            switch peek() {
            case .prefixedName(let p, let l):
                prefixName = l.isEmpty ? p : "\(p):\(l)"
                advance()
            case .a:
                prefixName = ""
                advance()
            default:
                // bare colon
                prefixName = ""
            }
            // Expect colon if not already consumed
            if peek() == .prefixedName("", "") {
                advance()
            }
            // IRI
            guard case .iri(let iriValue) = peek() else {
                throw SPARQLParseError.unexpectedToken(
                    expected: "IRI",
                    found: tokenDescription(peek()),
                    position: position
                )
            }
            advance()
            prefixes[prefixName] = iriValue
        }
        return prefixes
    }

    // MARK: - Projection

    private mutating func parseProjection() throws -> ParsedProjection {
        if consume(.star) {
            return .all
        }

        var items: [(ParsedFilterExpr, String)?] = []
        var variables: [String] = []
        var hasExpressions = false

        while !isAtEnd && peek() != .where_ {
            if peek() == .openParen {
                // Expression: (expr AS ?var)
                advance() // (
                let expr = try parseExpression()
                try expect(.as_)
                guard case .variable(let name) = peek() else {
                    throw SPARQLParseError.unexpectedToken(
                        expected: "variable",
                        found: tokenDescription(peek()),
                        position: position
                    )
                }
                advance()
                try expect(.closeParen)
                items.append((expr, name))
                hasExpressions = true
            } else if case .variable(let name) = peek() {
                advance()
                variables.append(name)
                items.append(nil)
            } else {
                break
            }
        }

        if hasExpressions {
            var expressions: [(ParsedFilterExpr, String)] = []
            for (idx, item) in items.enumerated() {
                if let item {
                    expressions.append(item)
                } else {
                    let name = variables.isEmpty ? "v\(idx)" : variables.removeFirst()
                    expressions.append((.term(.variable(name)), name))
                }
            }
            return .expressions(expressions)
        }

        return .variables(variables)
    }

    // MARK: - Group Graph Pattern

    private mutating func parseGroupGraphPattern() throws -> ParsedGraphPattern {
        try expect(.openBrace)
        let pattern = try parseGraphPatternContents()
        try expect(.closeBrace)
        return pattern
    }

    private mutating func parseGraphPatternContents() throws -> ParsedGraphPattern {
        var patterns: [ParsedTriplePattern] = []
        var result: ParsedGraphPattern?

        func flushBGP() {
            if !patterns.isEmpty {
                let bgp = ParsedGraphPattern.bgp(patterns)
                patterns = []
                if let existing = result {
                    result = .join(existing, bgp)
                } else {
                    result = bgp
                }
            }
        }

        while !isAtEnd && peek() != .closeBrace {
            switch peek() {
            case .filter:
                flushBGP()
                advance()
                try expect(.openParen)
                let expr = try parseExpression()
                try expect(.closeParen)
                if let existing = result {
                    result = .filter(existing, expr)
                } else {
                    result = .filter(.bgp([]), expr)
                }

            case .optional_:
                flushBGP()
                advance()
                let optPattern = try parseGroupGraphPattern()
                if let existing = result {
                    result = .optional_(existing, optPattern)
                } else {
                    result = .optional_(.bgp([]), optPattern)
                }

            case .bind:
                flushBGP()
                advance()
                try expect(.openParen)
                let expr = try parseExpression()
                try expect(.as_)
                guard case .variable(let name) = peek() else {
                    throw SPARQLParseError.unexpectedToken(
                        expected: "variable",
                        found: tokenDescription(peek()),
                        position: position
                    )
                }
                advance()
                try expect(.closeParen)
                if let existing = result {
                    result = .bind(existing, variable: name, expression: expr)
                } else {
                    result = .bind(.bgp([]), variable: name, expression: expr)
                }

            case .minus_:
                flushBGP()
                advance()
                let minusPattern = try parseGroupGraphPattern()
                if let existing = result {
                    result = .minus(existing, minusPattern)
                } else {
                    result = .minus(.bgp([]), minusPattern)
                }

            case .openBrace:
                // Nested group or UNION
                flushBGP()
                let nested = try parseGroupGraphPattern()
                var current = nested

                // Check for UNION
                while consume(.union) {
                    let right = try parseGroupGraphPattern()
                    current = .union(current, right)
                }

                if let existing = result {
                    result = .join(existing, current)
                } else {
                    result = current
                }

            default:
                // Triple patterns
                let newTriples = try parseTriplesSameSubject()
                patterns.append(contentsOf: newTriples)
                _ = consume(.dot)
            }
        }

        flushBGP()
        return result ?? .bgp([])
    }

    // MARK: - Triple Patterns

    private mutating func parseTriplesSameSubject() throws -> [ParsedTriplePattern] {
        let subject = try parseTerm()
        return try parsePropertyListNotEmpty(subject: subject)
    }

    private mutating func parsePropertyListNotEmpty(subject: ParsedTerm) throws -> [ParsedTriplePattern] {
        var triples: [ParsedTriplePattern] = []

        repeat {
            let predicate = try parseTerm()
            // Object list (comma-separated)
            repeat {
                let object = try parseTerm()
                triples.append(ParsedTriplePattern(
                    subject: subject, predicate: predicate, object: object
                ))
            } while consume(.comma)
        } while consume(.semicolon) && peek() != .dot && peek() != .closeBrace

        return triples
    }

    // MARK: - Terms

    private mutating func parseTerm() throws -> ParsedTerm {
        let token = peek()
        switch token {
        case .variable(let name):
            advance()
            return .variable(name)

        case .iri(let value):
            advance()
            return .iri(value)

        case .prefixedName(let prefix, let local):
            advance()
            return .prefixedName(prefix: prefix, local: local)

        case .a:
            advance()
            return .prefixedName(prefix: "rdf", local: "type")

        case .stringLiteral(let value):
            advance()
            // Check for ^^ datatype or @ lang
            if consume(.caretCaret) {
                let dtTerm = try parseTerm()
                switch dtTerm {
                case .iri(let dt):
                    return .typedLiteral(value: value, datatype: dt)
                case .prefixedName(let p, let l):
                    return .typedLiteral(value: value, datatype: "\(p):\(l)")
                default:
                    throw SPARQLParseError.invalidLiteral("Expected datatype IRI after ^^")
                }
            }
            if case .langTag(let lang) = peek() {
                advance()
                return .langLiteral(value: value, lang: lang)
            }
            return .stringLiteral(value)

        case .integerLiteral(let value):
            advance()
            return .integerLiteral(value)

        case .doubleLiteral(let value):
            advance()
            return .doubleLiteral(value)

        default:
            throw SPARQLParseError.unexpectedToken(
                expected: "term (variable, IRI, literal)",
                found: tokenDescription(token),
                position: position
            )
        }
    }

    // MARK: - Expressions

    private mutating func parseExpression() throws -> ParsedFilterExpr {
        try parseConditionalOrExpression()
    }

    private mutating func parseConditionalOrExpression() throws -> ParsedFilterExpr {
        var left = try parseConditionalAndExpression()
        while consume(.or) {
            let right = try parseConditionalAndExpression()
            left = .or(left, right)
        }
        return left
    }

    private mutating func parseConditionalAndExpression() throws -> ParsedFilterExpr {
        var left = try parseRelationalExpression()
        while consume(.and) {
            let right = try parseRelationalExpression()
            left = .and(left, right)
        }
        return left
    }

    private mutating func parseRelationalExpression() throws -> ParsedFilterExpr {
        let left = try parseAdditiveExpression()

        switch peek() {
        case .equal:
            advance()
            return .equal(left, try parseAdditiveExpression())
        case .notEqual:
            advance()
            return .notEqual(left, try parseAdditiveExpression())
        case .lessThan:
            advance()
            return .lessThan(left, try parseAdditiveExpression())
        case .greaterThan:
            advance()
            return .greaterThan(left, try parseAdditiveExpression())
        case .lessThanOrEqual:
            advance()
            return .lessThanOrEqual(left, try parseAdditiveExpression())
        case .greaterThanOrEqual:
            advance()
            return .greaterThanOrEqual(left, try parseAdditiveExpression())
        default:
            return left
        }
    }

    private mutating func parseAdditiveExpression() throws -> ParsedFilterExpr {
        var left = try parseMultiplicativeExpression()
        while true {
            if consume(.plus) {
                left = .add(left, try parseMultiplicativeExpression())
            } else if consume(.minus__) {
                left = .subtract(left, try parseMultiplicativeExpression())
            } else {
                break
            }
        }
        return left
    }

    private mutating func parseMultiplicativeExpression() throws -> ParsedFilterExpr {
        var left = try parseUnaryExpression()
        while true {
            if consume(.star) {
                left = .multiply(left, try parseUnaryExpression())
            } else if consume(.slash) {
                left = .divide(left, try parseUnaryExpression())
            } else {
                break
            }
        }
        return left
    }

    private mutating func parseUnaryExpression() throws -> ParsedFilterExpr {
        if consume(.bang) {
            return .not(try parseUnaryExpression())
        }
        return try parsePrimaryExpression()
    }

    private mutating func parsePrimaryExpression() throws -> ParsedFilterExpr {
        switch peek() {
        case .openParen:
            advance()
            let expr = try parseExpression()
            try expect(.closeParen)
            return expr

        case .bound:
            advance()
            try expect(.openParen)
            guard case .variable(let name) = peek() else {
                throw SPARQLParseError.unexpectedToken(
                    expected: "variable",
                    found: tokenDescription(peek()),
                    position: position
                )
            }
            advance()
            try expect(.closeParen)
            return .bound(name)

        case .isIRI:
            advance()
            try expect(.openParen)
            let expr = try parseExpression()
            try expect(.closeParen)
            return .isIRI(expr)

        case .isLiteral:
            advance()
            try expect(.openParen)
            let expr = try parseExpression()
            try expect(.closeParen)
            return .isLiteral(expr)

        case .str:
            advance()
            try expect(.openParen)
            let expr = try parseExpression()
            try expect(.closeParen)
            return .str(expr)

        case .lang:
            advance()
            try expect(.openParen)
            let expr = try parseExpression()
            try expect(.closeParen)
            return .lang(expr)

        case .regex:
            advance()
            try expect(.openParen)
            let expr = try parseExpression()
            try expect(.comma)
            guard case .stringLiteral(let pattern) = peek() else {
                throw SPARQLParseError.unexpectedToken(
                    expected: "string literal (regex pattern)",
                    found: tokenDescription(peek()),
                    position: position
                )
            }
            advance()
            var flags: String?
            if consume(.comma) {
                guard case .stringLiteral(let f) = peek() else {
                    throw SPARQLParseError.unexpectedToken(
                        expected: "string literal (regex flags)",
                        found: tokenDescription(peek()),
                        position: position
                    )
                }
                advance()
                flags = f
            }
            try expect(.closeParen)
            return .regex(expr, pattern: pattern, flags: flags)

        case .count, .sum, .avg, .fnMin, .fnMax:
            return try .aggregate(parseAggregate())

        default:
            let term = try parseTerm()
            return .term(term)
        }
    }

    // MARK: - Aggregates

    private mutating func parseAggregate() throws -> ParsedAggregate {
        let aggToken = peek()
        advance()
        try expect(.openParen)

        switch aggToken {
        case .count:
            let distinct = consume(.distinct)
            if consume(.star) {
                try expect(.closeParen)
                return .count(nil, distinct: distinct)
            }
            let expr = try parseExpression()
            try expect(.closeParen)
            return .count(expr, distinct: distinct)

        case .sum:
            let distinct = consume(.distinct)
            let expr = try parseExpression()
            try expect(.closeParen)
            return .sum(expr, distinct: distinct)

        case .avg:
            let distinct = consume(.distinct)
            let expr = try parseExpression()
            try expect(.closeParen)
            return .avg(expr, distinct: distinct)

        case .fnMin:
            let expr = try parseExpression()
            try expect(.closeParen)
            return .min(expr)

        case .fnMax:
            let expr = try parseExpression()
            try expect(.closeParen)
            return .max(expr)

        default:
            throw SPARQLParseError.unsupportedFeature("Unknown aggregate")
        }
    }

    // MARK: - Clauses

    private mutating func parseGroupByClause() throws -> [ParsedFilterExpr]? {
        guard consume(.groupBy) else { return nil }
        var keys: [ParsedFilterExpr] = []
        while !isAtEnd && peek() != .having && peek() != .orderBy
                && peek() != .limit && peek() != .offset && peek() != .eof {
            if case .variable(let name) = peek() {
                advance()
                keys.append(.term(.variable(name)))
            } else {
                break
            }
        }
        return keys.isEmpty ? nil : keys
    }

    private mutating func parseHavingClause() throws -> ParsedFilterExpr? {
        guard consume(.having) else { return nil }
        try expect(.openParen)
        let expr = try parseExpression()
        try expect(.closeParen)
        return expr
    }

    private mutating func parseOrderByClause() throws -> [ParsedOrderKey]? {
        guard consume(.orderBy) else { return nil }
        var keys: [ParsedOrderKey] = []

        while !isAtEnd && peek() != .limit && peek() != .offset && peek() != .eof {
            if consume(.asc) {
                try expect(.openParen)
                let expr = try parseExpression()
                try expect(.closeParen)
                keys.append(ParsedOrderKey(expression: expr, ascending: true))
            } else if consume(.desc) {
                try expect(.openParen)
                let expr = try parseExpression()
                try expect(.closeParen)
                keys.append(ParsedOrderKey(expression: expr, ascending: false))
            } else if case .variable = peek() {
                let expr = try parseExpression()
                keys.append(ParsedOrderKey(expression: expr, ascending: true))
            } else {
                break
            }
        }
        return keys.isEmpty ? nil : keys
    }

    private mutating func parseLimitOffset() -> (Int?, Int?) {
        var limit: Int?
        var offset: Int?

        for _ in 0..<2 {
            if consume(.limit) {
                if case .integerLiteral(let n) = peek() {
                    advance()
                    limit = Int(n)
                }
            } else if consume(.offset) {
                if case .integerLiteral(let n) = peek() {
                    advance()
                    offset = Int(n)
                }
            }
        }
        return (limit, offset)
    }

    // MARK: - Utilities

    private var isAtEnd: Bool {
        position >= tokens.count || tokens[position] == .eof
    }

    private func peek() -> SPARQLToken {
        guard position < tokens.count else { return .eof }
        return tokens[position]
    }

    private mutating func advance() {
        position += 1
    }

    @discardableResult
    private mutating func consume(_ token: SPARQLToken) -> Bool {
        if peek() == token {
            advance()
            return true
        }
        return false
    }

    private mutating func expect(_ token: SPARQLToken) throws {
        guard consume(token) else {
            throw SPARQLParseError.unexpectedToken(
                expected: tokenDescription(token),
                found: tokenDescription(peek()),
                position: position
            )
        }
    }

    private func tokenDescription(_ token: SPARQLToken) -> String {
        switch token {
        case .select: return "SELECT"
        case .distinct: return "DISTINCT"
        case .where_: return "WHERE"
        case .limit: return "LIMIT"
        case .offset: return "OFFSET"
        case .orderBy: return "ORDER BY"
        case .groupBy: return "GROUP BY"
        case .having: return "HAVING"
        case .asc: return "ASC"
        case .desc: return "DESC"
        case .filter: return "FILTER"
        case .optional_: return "OPTIONAL"
        case .union: return "UNION"
        case .minus_: return "MINUS"
        case .bind: return "BIND"
        case .as_: return "AS"
        case .prefix_: return "PREFIX"
        case .count: return "COUNT"
        case .sum: return "SUM"
        case .avg: return "AVG"
        case .fnMin: return "MIN"
        case .fnMax: return "MAX"
        case .separator: return "SEPARATOR"
        case .bound: return "BOUND"
        case .isIRI: return "isIRI"
        case .isLiteral: return "isLiteral"
        case .isBlank: return "isBlank"
        case .str: return "STR"
        case .lang: return "LANG"
        case .datatype: return "DATATYPE"
        case .regex: return "REGEX"
        case .openBrace: return "{"
        case .closeBrace: return "}"
        case .openParen: return "("
        case .closeParen: return ")"
        case .dot: return "."
        case .semicolon: return ";"
        case .comma: return ","
        case .star: return "*"
        case .equal: return "="
        case .notEqual: return "!="
        case .lessThan: return "<"
        case .greaterThan: return ">"
        case .lessThanOrEqual: return "<="
        case .greaterThanOrEqual: return ">="
        case .and: return "&&"
        case .or: return "||"
        case .bang: return "!"
        case .plus: return "+"
        case .minus__: return "-"
        case .slash: return "/"
        case .caretCaret: return "^^"
        case .variable(let n): return "?\(n)"
        case .iri(let v): return "<\(v)>"
        case .prefixedName(let p, let l): return "\(p):\(l)"
        case .stringLiteral(let v): return "\"\(v)\""
        case .integerLiteral(let v): return "\(v)"
        case .doubleLiteral(let v): return "\(v)"
        case .langTag(let v): return "@\(v)"
        case .a: return "a"
        case .eof: return "end of input"
        }
    }
}
