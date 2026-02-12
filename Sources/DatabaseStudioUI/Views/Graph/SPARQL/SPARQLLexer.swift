/// SPARQL テキストをトークン列に変換するレキサー
struct SPARQLLexer: Sendable {
    private let input: [Character]
    private var position: Int

    init(input: String) {
        self.input = Array(input)
        self.position = 0
    }

    /// 全トークンを一括で生成
    mutating func tokenize() throws -> [SPARQLToken] {
        var tokens: [SPARQLToken] = []
        while true {
            let token = try nextToken()
            tokens.append(token)
            if token == .eof { break }
        }
        return tokens
    }

    // MARK: - Token Production

    mutating func nextToken() throws -> SPARQLToken {
        skipWhitespaceAndComments()

        guard position < input.count else {
            return .eof
        }

        let ch = input[position]

        switch ch {
        case "{": position += 1; return .openBrace
        case "}": position += 1; return .closeBrace
        case "(": position += 1; return .openParen
        case ")": position += 1; return .closeParen
        case ".": position += 1; return .dot
        case ";": position += 1; return .semicolon
        case ",": position += 1; return .comma
        case "*": position += 1; return .star
        case "/": position += 1; return .slash
        case "+": position += 1; return .plus
        case "=": position += 1; return .equal

        case "!":
            position += 1
            if position < input.count && input[position] == "=" {
                position += 1
                return .notEqual
            }
            return .bang

        case "&":
            position += 1
            if position < input.count && input[position] == "&" {
                position += 1
                return .and
            }
            throw SPARQLParseError.unexpectedToken(
                expected: "&&", found: "&", position: position - 1
            )

        case "|":
            position += 1
            if position < input.count && input[position] == "|" {
                position += 1
                return .or
            }
            throw SPARQLParseError.unexpectedToken(
                expected: "||", found: "|", position: position - 1
            )

        case "<":
            position += 1
            if position < input.count && input[position] == "=" {
                position += 1
                return .lessThanOrEqual
            }
            // IRI: <...>
            if position < input.count && isIRIStartChar(input[position]) {
                return try readIRI()
            }
            return .lessThan

        case ">":
            position += 1
            if position < input.count && input[position] == "=" {
                position += 1
                return .greaterThanOrEqual
            }
            return .greaterThan

        case "^":
            position += 1
            if position < input.count && input[position] == "^" {
                position += 1
                return .caretCaret
            }
            throw SPARQLParseError.unexpectedToken(
                expected: "^^", found: "^", position: position - 1
            )

        case "?", "$":
            return readVariable()

        case "\"", "'":
            return try readStringLiteral()

        case "@":
            return readLangTag()

        case "-":
            position += 1
            if position < input.count && input[position].isNumber {
                let num = try readNumber(negative: true)
                return num
            }
            return .minus__

        default:
            if ch.isNumber {
                return try readNumber(negative: false)
            }
            if isNameStartChar(ch) {
                return readNameOrKeyword()
            }
            throw SPARQLParseError.unexpectedToken(
                expected: "valid token", found: String(ch), position: position
            )
        }
    }

    // MARK: - Helpers

    private mutating func skipWhitespaceAndComments() {
        while position < input.count {
            let ch = input[position]
            if ch.isWhitespace {
                position += 1
            } else if ch == "#" {
                // Line comment
                while position < input.count && input[position] != "\n" {
                    position += 1
                }
            } else {
                break
            }
        }
    }

    private mutating func readVariable() -> SPARQLToken {
        position += 1 // skip ? or $
        let start = position
        while position < input.count && isNameChar(input[position]) {
            position += 1
        }
        let name = String(input[start..<position])
        return .variable(name)
    }

    private mutating func readIRI() throws -> SPARQLToken {
        // position is after '<', read until '>'
        let start = position
        while position < input.count && input[position] != ">" {
            position += 1
        }
        guard position < input.count else {
            throw SPARQLParseError.invalidIRI(String(input[start..<position]))
        }
        let iri = String(input[start..<position])
        position += 1 // skip '>'
        return .iri(iri)
    }

    private mutating func readStringLiteral() throws -> SPARQLToken {
        let quote = input[position]
        position += 1
        var value: [Character] = []

        while position < input.count && input[position] != quote {
            if input[position] == "\\" {
                position += 1
                guard position < input.count else {
                    throw SPARQLParseError.invalidLiteral("Unterminated escape sequence")
                }
                switch input[position] {
                case "n": value.append("\n")
                case "t": value.append("\t")
                case "r": value.append("\r")
                case "\\": value.append("\\")
                case "\"": value.append("\"")
                case "'": value.append("'")
                default: value.append(input[position])
                }
            } else {
                value.append(input[position])
            }
            position += 1
        }

        guard position < input.count else {
            throw SPARQLParseError.invalidLiteral("Unterminated string literal")
        }
        position += 1 // skip closing quote
        return .stringLiteral(String(value))
    }

    private mutating func readLangTag() -> SPARQLToken {
        position += 1 // skip @
        let start = position
        while position < input.count && (input[position].isLetter || input[position] == "-") {
            position += 1
        }
        return .langTag(String(input[start..<position]))
    }

    private mutating func readNumber(negative: Bool) throws -> SPARQLToken {
        let start = negative ? position - 1 : position
        var isDouble = false

        while position < input.count && input[position].isNumber {
            position += 1
        }
        if position < input.count && input[position] == "." {
            // Check it's not a trailing dot (end of triple pattern)
            if position + 1 < input.count && input[position + 1].isNumber {
                isDouble = true
                position += 1
                while position < input.count && input[position].isNumber {
                    position += 1
                }
            }
        }
        if position < input.count && (input[position] == "e" || input[position] == "E") {
            isDouble = true
            position += 1
            if position < input.count && (input[position] == "+" || input[position] == "-") {
                position += 1
            }
            while position < input.count && input[position].isNumber {
                position += 1
            }
        }

        let raw = String(input[start..<position])
        if isDouble {
            guard let d = Double(raw) else {
                throw SPARQLParseError.invalidLiteral(raw)
            }
            return .doubleLiteral(d)
        } else {
            guard let i = Int64(raw) else {
                throw SPARQLParseError.invalidLiteral(raw)
            }
            return .integerLiteral(i)
        }
    }

    private mutating func readNameOrKeyword() -> SPARQLToken {
        let start = position
        while position < input.count && isNameChar(input[position]) {
            position += 1
        }

        let word = String(input[start..<position])

        // Check for prefixed name (word:local)
        if position < input.count && input[position] == ":" {
            position += 1 // skip ':'
            let localStart = position
            while position < input.count && isNameChar(input[position]) {
                position += 1
            }
            let local = String(input[localStart..<position])
            return .prefixedName(word, local)
        }

        // Keywords (case-insensitive)
        switch word.uppercased() {
        case "SELECT": return .select
        case "DISTINCT": return .distinct
        case "WHERE": return .where_
        case "LIMIT": return .limit
        case "OFFSET": return .offset
        case "ORDER": return consumeByKeyword()
        case "GROUP": return consumeGroupByKeyword()
        case "HAVING": return .having
        case "ASC": return .asc
        case "DESC": return .desc
        case "FILTER": return .filter
        case "OPTIONAL": return .optional_
        case "UNION": return .union
        case "MINUS": return .minus_
        case "BIND": return .bind
        case "AS": return .as_
        case "PREFIX": return .prefix_
        case "COUNT": return .count
        case "SUM": return .sum
        case "AVG": return .avg
        case "MIN": return .fnMin
        case "MAX": return .fnMax
        case "SEPARATOR": return .separator
        case "BOUND": return .bound
        case "ISIRI", "ISURI": return .isIRI
        case "ISLITERAL": return .isLiteral
        case "ISBLANK": return .isBlank
        case "STR": return .str
        case "LANG": return .lang
        case "DATATYPE": return .datatype
        case "REGEX": return .regex
        case "A": return .a
        case "TRUE": return .integerLiteral(1) // boolean true
        case "FALSE": return .integerLiteral(0) // boolean false
        default:
            // Bare name without colon — treat as prefixed name with empty local
            // or as an identifier. Check if it looks like "prefix:" was intended.
            return .prefixedName("", word)
        }
    }

    /// Consume "BY" after "ORDER" to produce .orderBy
    private mutating func consumeByKeyword() -> SPARQLToken {
        skipWhitespaceAndComments()
        let saved = position
        if position < input.count && isNameStartChar(input[position]) {
            let start = position
            while position < input.count && isNameChar(input[position]) {
                position += 1
            }
            let word = String(input[start..<position])
            if word.uppercased() == "BY" {
                return .orderBy
            }
            position = saved
        }
        return .prefixedName("", "ORDER")
    }

    /// Consume "BY" after "GROUP" to produce .groupBy
    private mutating func consumeGroupByKeyword() -> SPARQLToken {
        skipWhitespaceAndComments()
        let saved = position
        if position < input.count && isNameStartChar(input[position]) {
            let start = position
            while position < input.count && isNameChar(input[position]) {
                position += 1
            }
            let word = String(input[start..<position])
            if word.uppercased() == "BY" {
                return .groupBy
            }
            position = saved
        }
        return .prefixedName("", "GROUP")
    }

    // MARK: - Character Classification

    private func isNameStartChar(_ ch: Character) -> Bool {
        ch.isLetter || ch == "_"
    }

    private func isNameChar(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "."
    }

    private func isIRIStartChar(_ ch: Character) -> Bool {
        ch != ">" && ch != " " && ch != "\n"
    }
}
