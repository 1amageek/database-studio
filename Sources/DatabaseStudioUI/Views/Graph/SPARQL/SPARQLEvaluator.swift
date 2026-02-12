import Foundation

/// バインディング（変数名 → 値）
typealias SPARQLBinding = [String: String]

/// SPARQL クエリをインメモリトリプルストアに対して評価する
struct SPARQLEvaluator: Sendable {

    private let store: InMemoryTripleStore
    private let prefixes: [String: String]

    /// 中間結果の安全上限
    private static let maxIntermediateResults = 100_000

    /// 共通プレフィックス
    private static let defaultPrefixes: [String: String] = [
        "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
        "owl": "http://www.w3.org/2002/07/owl#",
        "xsd": "http://www.w3.org/2001/XMLSchema#",
    ]

    init(store: InMemoryTripleStore, prefixes: [String: String]) {
        var merged = Self.defaultPrefixes
        for (k, v) in prefixes {
            merged[k] = v
        }
        self.store = store
        self.prefixes = merged
    }

    /// クエリを評価し、カラム名と結果行を返す
    func evaluate(_ query: ParsedSPARQLQuery) throws -> (columns: [String], rows: [SPARQLBinding]) {
        // WHERE 節を評価
        var bindings = try evaluatePattern(query.wherePattern)

        // GROUP BY
        if let groupExprs = query.groupBy {
            bindings = try evaluateGroupBy(
                bindings: bindings,
                groupExprs: groupExprs,
                projection: query.projection,
                having: query.having
            )
        } else if projectionHasAggregates(query.projection) {
            // GROUP BY なしで集計関数がある場合、全体を1グループとして扱う
            bindings = try evaluateGroupBy(
                bindings: bindings,
                groupExprs: [],
                projection: query.projection,
                having: query.having
            )
        }

        // ORDER BY
        if let orderKeys = query.orderBy {
            bindings = sortBindings(bindings, by: orderKeys)
        }

        // DISTINCT
        if query.isDistinct {
            bindings = distinctBindings(bindings)
        }

        // OFFSET
        if let offset = query.offset, offset > 0 {
            bindings = Array(bindings.dropFirst(offset))
        }

        // LIMIT
        if let limit = query.limit {
            bindings = Array(bindings.prefix(limit))
        }

        // Projection
        let (columns, projected) = projectBindings(bindings, projection: query.projection)

        return (columns, projected)
    }

    // MARK: - Pattern Evaluation

    private func evaluatePattern(_ pattern: ParsedGraphPattern) throws -> [SPARQLBinding] {
        switch pattern {
        case .bgp(let triplePatterns):
            return try evaluateBGP(triplePatterns)

        case .join(let left, let right):
            let leftBindings = try evaluatePattern(left)
            return try joinBindings(leftBindings, with: right)

        case .optional_(let left, let right):
            let leftBindings = try evaluatePattern(left)
            return try optionalJoin(leftBindings, with: right)

        case .union(let left, let right):
            let leftBindings = try evaluatePattern(left)
            let rightBindings = try evaluatePattern(right)
            return leftBindings + rightBindings

        case .minus(let left, let right):
            let leftBindings = try evaluatePattern(left)
            let rightBindings = try evaluatePattern(right)
            return minusBindings(leftBindings, minus: rightBindings)

        case .filter(let inner, let expr):
            let bindings = try evaluatePattern(inner)
            return try bindings.filter { binding in
                let result = try evaluateFilterExpr(expr, binding: binding)
                return result.isTruthy
            }

        case .bind(let inner, let variable, let expression):
            let bindings = try evaluatePattern(inner)
            return try bindings.map { binding in
                var newBinding = binding
                let value = try evaluateFilterExpr(expression, binding: binding)
                newBinding[variable] = value.stringValue
                return newBinding
            }
        }
    }

    // MARK: - BGP Evaluation

    private func evaluateBGP(_ patterns: [ParsedTriplePattern]) throws -> [SPARQLBinding] {
        guard !patterns.isEmpty else {
            return [[:]] // 1つの空バインディング
        }

        var bindings: [SPARQLBinding] = [[:]]

        for pattern in patterns {
            var newBindings: [SPARQLBinding] = []
            for existing in bindings {
                let matches = try matchPattern(pattern, with: existing)
                newBindings.append(contentsOf: matches)

                if newBindings.count > Self.maxIntermediateResults {
                    throw SPARQLEvaluatorError.resultTooLarge(newBindings.count)
                }
            }
            bindings = newBindings
        }

        return bindings
    }

    private func matchPattern(_ pattern: ParsedTriplePattern, with binding: SPARQLBinding) throws -> [SPARQLBinding] {
        let s = resolveTerm(pattern.subject, binding: binding)
        let p = resolveTerm(pattern.predicate, binding: binding)
        let o = resolveTerm(pattern.object, binding: binding)

        let matches = store.match(subject: s, predicate: p, object: o)

        return matches.compactMap { triple in
            var newBinding = binding
            if !bindVariable(pattern.subject, value: triple.subject, into: &newBinding) { return nil }
            if !bindVariable(pattern.predicate, value: triple.predicate, into: &newBinding) { return nil }
            if !bindVariable(pattern.object, value: triple.object, into: &newBinding) { return nil }
            return newBinding
        }
    }

    /// 項を具体値に解決（変数ならバインディングから参照、定数ならそのまま）
    private func resolveTerm(_ term: ParsedTerm, binding: SPARQLBinding) -> String? {
        switch term {
        case .variable(let name):
            return binding[name]
        case .iri(let value):
            return value
        case .prefixedName(let prefix, let local):
            if let base = prefixes[prefix] {
                return "\(base)\(local)"
            }
            return "\(prefix):\(local)"
        case .stringLiteral(let value):
            return "\"\(value)\""
        case .typedLiteral(let value, let dt):
            return "\"\(value)\"^^<\(dt)>"
        case .langLiteral(let value, let lang):
            return "\"\(value)\"@\(lang)"
        case .integerLiteral(let value):
            return "\"\(value)\""
        case .doubleLiteral(let value):
            return "\"\(value)\""
        }
    }

    /// 変数項の場合、トリプルの値をバインディングに追加（整合性チェック付き）
    private func bindVariable(_ term: ParsedTerm, value: String, into binding: inout SPARQLBinding) -> Bool {
        guard case .variable(let name) = term else { return true }
        if let existing = binding[name] {
            return existing == value
        }
        binding[name] = value
        return true
    }

    // MARK: - Join / Optional / Minus

    private func joinBindings(_ leftBindings: [SPARQLBinding], with rightPattern: ParsedGraphPattern) throws -> [SPARQLBinding] {
        var result: [SPARQLBinding] = []
        for binding in leftBindings {
            let rightBindings = try evaluatePattern(rightPattern)
            for right in rightBindings {
                if let merged = mergeBindings(binding, right) {
                    result.append(merged)
                }
            }
        }
        return result
    }

    private func optionalJoin(_ leftBindings: [SPARQLBinding], with rightPattern: ParsedGraphPattern) throws -> [SPARQLBinding] {
        var result: [SPARQLBinding] = []
        for binding in leftBindings {
            let rightResults = try evaluatePatternWithBinding(rightPattern, existing: binding)
            if rightResults.isEmpty {
                result.append(binding)
            } else {
                result.append(contentsOf: rightResults)
            }
        }
        return result
    }

    private func evaluatePatternWithBinding(_ pattern: ParsedGraphPattern, existing: SPARQLBinding) throws -> [SPARQLBinding] {
        let raw = try evaluatePattern(pattern)
        return raw.compactMap { mergeBindings(existing, $0) }
    }

    private func minusBindings(_ left: [SPARQLBinding], minus right: [SPARQLBinding]) -> [SPARQLBinding] {
        left.filter { leftBinding in
            !right.contains { rightBinding in
                bindingsCompatible(leftBinding, rightBinding)
            }
        }
    }

    private func mergeBindings(_ a: SPARQLBinding, _ b: SPARQLBinding) -> SPARQLBinding? {
        var merged = a
        for (key, value) in b {
            if let existing = merged[key] {
                if existing != value { return nil }
            } else {
                merged[key] = value
            }
        }
        return merged
    }

    private func bindingsCompatible(_ a: SPARQLBinding, _ b: SPARQLBinding) -> Bool {
        for (key, value) in b {
            if let existing = a[key], existing != value {
                return false
            }
        }
        // Compatible if shared variables have the same values
        let shared = Set(a.keys).intersection(Set(b.keys))
        return !shared.isEmpty
    }

    // MARK: - Filter Expression Evaluation

    private func evaluateFilterExpr(_ expr: ParsedFilterExpr, binding: SPARQLBinding) throws -> FilterValue {
        switch expr {
        case .term(let term):
            return termToFilterValue(term, binding: binding)

        case .equal(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return .boolean(lv.compareEqual(to: rv))

        case .notEqual(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return .boolean(!lv.compareEqual(to: rv))

        case .lessThan(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return .boolean(lv.compareLessThan(rv))

        case .greaterThan(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return .boolean(rv.compareLessThan(lv))

        case .lessThanOrEqual(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return .boolean(lv.compareEqual(to: rv) || lv.compareLessThan(rv))

        case .greaterThanOrEqual(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return .boolean(lv.compareEqual(to: rv) || rv.compareLessThan(lv))

        case .and(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return .boolean(lv.isTruthy && rv.isTruthy)

        case .or(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return .boolean(lv.isTruthy || rv.isTruthy)

        case .not(let inner):
            let v = try evaluateFilterExpr(inner, binding: binding)
            return .boolean(!v.isTruthy)

        case .add(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return lv.add(rv)

        case .subtract(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return lv.subtract(rv)

        case .multiply(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return lv.multiply(rv)

        case .divide(let l, let r):
            let lv = try evaluateFilterExpr(l, binding: binding)
            let rv = try evaluateFilterExpr(r, binding: binding)
            return try lv.divide(rv)

        case .bound(let name):
            return .boolean(binding[name] != nil)

        case .isIRI(let inner):
            let v = try evaluateFilterExpr(inner, binding: binding)
            return .boolean(!v.stringValue.hasPrefix("\""))

        case .isLiteral(let inner):
            let v = try evaluateFilterExpr(inner, binding: binding)
            return .boolean(v.stringValue.hasPrefix("\""))

        case .str(let inner):
            let v = try evaluateFilterExpr(inner, binding: binding)
            return .string(v.plainStringValue)

        case .lang(let inner):
            let v = try evaluateFilterExpr(inner, binding: binding)
            let raw = v.stringValue
            if let atRange = raw.range(of: "\"@", options: .backwards) {
                return .string(String(raw[atRange.upperBound...]))
            }
            return .string("")

        case .regex(let inner, let pattern, let flags):
            let v = try evaluateFilterExpr(inner, binding: binding)
            let text = v.plainStringValue
            var options: NSRegularExpression.Options = []
            if let flags, flags.contains("i") {
                options.insert(.caseInsensitive)
            }
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: options)
                let range = NSRange(text.startIndex..., in: text)
                return .boolean(regex.firstMatch(in: text, range: range) != nil)
            } catch {
                throw SPARQLEvaluatorError.invalidRegex(pattern)
            }

        case .aggregate:
            // Aggregates are handled in GROUP BY evaluation
            return .string("")
        }
    }

    private func termToFilterValue(_ term: ParsedTerm, binding: SPARQLBinding) -> FilterValue {
        switch term {
        case .variable(let name):
            if let value = binding[name] {
                return FilterValue.fromRawValue(value)
            }
            return .unbound

        case .iri(let value):
            return .string(value)

        case .prefixedName(let prefix, let local):
            if let base = prefixes[prefix] {
                return .string("\(base)\(local)")
            }
            return .string("\(prefix):\(local)")

        case .stringLiteral(let value):
            return .string(value)

        case .typedLiteral(let value, _):
            if let n = Int64(value) { return .integer(n) }
            if let d = Double(value) { return .double(d) }
            return .string(value)

        case .langLiteral(let value, _):
            return .string(value)

        case .integerLiteral(let value):
            return .integer(value)

        case .doubleLiteral(let value):
            return .double(value)
        }
    }

    // MARK: - GROUP BY / Aggregation

    private func projectionHasAggregates(_ projection: ParsedProjection) -> Bool {
        switch projection {
        case .all, .variables: return false
        case .expressions(let exprs):
            return exprs.contains { exprContainsAggregate($0.0) }
        }
    }

    private func exprContainsAggregate(_ expr: ParsedFilterExpr) -> Bool {
        switch expr {
        case .aggregate: return true
        case .add(let l, let r), .subtract(let l, let r),
             .multiply(let l, let r), .divide(let l, let r),
             .equal(let l, let r), .notEqual(let l, let r),
             .lessThan(let l, let r), .greaterThan(let l, let r),
             .lessThanOrEqual(let l, let r), .greaterThanOrEqual(let l, let r),
             .and(let l, let r), .or(let l, let r):
            return exprContainsAggregate(l) || exprContainsAggregate(r)
        case .not(let inner), .isIRI(let inner), .isLiteral(let inner),
             .str(let inner), .lang(let inner):
            return exprContainsAggregate(inner)
        default: return false
        }
    }

    private func evaluateGroupBy(
        bindings: [SPARQLBinding],
        groupExprs: [ParsedFilterExpr],
        projection: ParsedProjection,
        having: ParsedFilterExpr?
    ) throws -> [SPARQLBinding] {
        // Build groups
        var groups: [[SPARQLBinding]] = []
        var groupKeys: [String] = []

        if groupExprs.isEmpty {
            // Single group for all rows
            groups = [bindings]
            groupKeys = [""]
        } else {
            var groupMap: [String: [SPARQLBinding]] = [:]
            var keyOrder: [String] = []
            for binding in bindings {
                let key = groupExprs.map { expr -> String in
                    let val = (try? evaluateFilterExpr(expr, binding: binding))?.stringValue ?? ""
                    return val
                }.joined(separator: "\0")

                if groupMap[key] == nil {
                    keyOrder.append(key)
                }
                groupMap[key, default: []].append(binding)
            }
            for key in keyOrder {
                groups.append(groupMap[key]!)
                groupKeys.append(key)
            }
        }

        // Evaluate projection with aggregates for each group
        guard case .expressions(let projExprs) = projection else {
            // Variables-only projection with GROUP BY: take first row of each group + group keys
            return groups.compactMap(\.first)
        }

        var result: [SPARQLBinding] = []

        for group in groups {
            var row: SPARQLBinding = [:]

            // Carry over group key values from first binding
            if let first = group.first {
                for expr in groupExprs {
                    if case .term(.variable(let name)) = expr {
                        row[name] = first[name]
                    }
                }
            }

            for (expr, alias) in projExprs {
                let value = try evaluateAggregateExpr(expr, group: group)
                row[alias] = value.stringValue
            }

            // HAVING filter
            if let having {
                let pass = try evaluateFilterExpr(having, binding: row)
                if !pass.isTruthy { continue }
            }

            result.append(row)
        }

        return result
    }

    private func evaluateAggregateExpr(_ expr: ParsedFilterExpr, group: [SPARQLBinding]) throws -> FilterValue {
        switch expr {
        case .aggregate(let agg):
            return try evaluateAggregate(agg, group: group)
        case .term(let term):
            if let first = group.first {
                return termToFilterValue(term, binding: first)
            }
            return .unbound
        case .add(let l, let r):
            let lv = try evaluateAggregateExpr(l, group: group)
            let rv = try evaluateAggregateExpr(r, group: group)
            return lv.add(rv)
        case .subtract(let l, let r):
            let lv = try evaluateAggregateExpr(l, group: group)
            let rv = try evaluateAggregateExpr(r, group: group)
            return lv.subtract(rv)
        case .multiply(let l, let r):
            let lv = try evaluateAggregateExpr(l, group: group)
            let rv = try evaluateAggregateExpr(r, group: group)
            return lv.multiply(rv)
        case .divide(let l, let r):
            let lv = try evaluateAggregateExpr(l, group: group)
            let rv = try evaluateAggregateExpr(r, group: group)
            return try lv.divide(rv)
        default:
            if let first = group.first {
                return try evaluateFilterExpr(expr, binding: first)
            }
            return .unbound
        }
    }

    private func evaluateAggregate(_ agg: ParsedAggregate, group: [SPARQLBinding]) throws -> FilterValue {
        switch agg {
        case .count(let expr, let distinct):
            if expr == nil {
                return .integer(Int64(distinct ? Set(group.map { $0.description }).count : group.count))
            }
            var values: [String] = []
            for binding in group {
                let v = try evaluateFilterExpr(expr!, binding: binding)
                if case .unbound = v { continue }
                values.append(v.stringValue)
            }
            if distinct {
                return .integer(Int64(Set(values).count))
            }
            return .integer(Int64(values.count))

        case .sum(let expr, let distinct):
            var vals: [Double] = []
            for binding in group {
                let v = try evaluateFilterExpr(expr, binding: binding)
                if let d = v.numericValue { vals.append(d) }
            }
            if distinct { return .double(Set(vals).reduce(0, +)) }
            return .double(vals.reduce(0, +))

        case .avg(let expr, let distinct):
            var vals: [Double] = []
            for binding in group {
                let v = try evaluateFilterExpr(expr, binding: binding)
                if let d = v.numericValue { vals.append(d) }
            }
            let uniqueVals = distinct ? Array(Set(vals)) : vals
            guard !uniqueVals.isEmpty else { return .double(0) }
            return .double(uniqueVals.reduce(0, +) / Double(uniqueVals.count))

        case .min(let expr):
            var minVal: FilterValue = .unbound
            for binding in group {
                let v = try evaluateFilterExpr(expr, binding: binding)
                if case .unbound = minVal {
                    minVal = v
                } else if v.compareLessThan(minVal) {
                    minVal = v
                }
            }
            return minVal

        case .max(let expr):
            var maxVal: FilterValue = .unbound
            for binding in group {
                let v = try evaluateFilterExpr(expr, binding: binding)
                if case .unbound = maxVal {
                    maxVal = v
                } else if maxVal.compareLessThan(v) {
                    maxVal = v
                }
            }
            return maxVal
        }
    }

    // MARK: - ORDER BY

    private func sortBindings(_ bindings: [SPARQLBinding], by keys: [ParsedOrderKey]) -> [SPARQLBinding] {
        bindings.sorted { a, b in
            for key in keys {
                let av = (try? evaluateFilterExpr(key.expression, binding: a)) ?? .unbound
                let bv = (try? evaluateFilterExpr(key.expression, binding: b)) ?? .unbound
                if av.compareEqual(to: bv) { continue }
                let less = av.compareLessThan(bv)
                return key.ascending ? less : !less
            }
            return false
        }
    }

    // MARK: - DISTINCT

    private func distinctBindings(_ bindings: [SPARQLBinding]) -> [SPARQLBinding] {
        var seen: Set<String> = []
        return bindings.filter { binding in
            let key = binding.sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "\0")
            return seen.insert(key).inserted
        }
    }

    // MARK: - Projection

    private func projectBindings(_ bindings: [SPARQLBinding], projection: ParsedProjection) -> (columns: [String], rows: [SPARQLBinding]) {
        switch projection {
        case .all:
            var allVars: [String] = []
            var seen: Set<String> = []
            for binding in bindings {
                for key in binding.keys.sorted() {
                    if seen.insert(key).inserted {
                        allVars.append(key)
                    }
                }
            }
            let projected = bindings.map { binding in
                var row: SPARQLBinding = [:]
                for v in allVars {
                    row[v] = formatOutputValue(binding[v])
                }
                return row
            }
            return (allVars, projected)

        case .variables(let vars):
            let projected = bindings.map { binding in
                var row: SPARQLBinding = [:]
                for v in vars {
                    row[v] = formatOutputValue(binding[v])
                }
                return row
            }
            return (vars, projected)

        case .expressions(let exprs):
            let columns = exprs.map(\.1)
            let projected = bindings.map { binding in
                var row: SPARQLBinding = [:]
                for (_, alias) in exprs {
                    row[alias] = formatOutputValue(binding[alias])
                }
                return row
            }
            return (columns, projected)
        }
    }

    /// 出力用に値をフォーマット（リテラル引用符を除去）
    private func formatOutputValue(_ raw: String?) -> String {
        guard let raw else { return "" }
        // リテラル形式 "value" → value
        if raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 {
            let start = raw.index(after: raw.startIndex)
            let end = raw.index(before: raw.endIndex)
            return String(raw[start..<end])
        }
        // 型付きリテラル "value"^^<type> → value
        if raw.hasPrefix("\""), let quoteEnd = raw.dropFirst().firstIndex(of: "\"") {
            return String(raw[raw.index(after: raw.startIndex)..<quoteEnd])
        }
        return raw
    }
}

// MARK: - FilterValue

/// フィルター式評価の中間値
enum FilterValue: Sendable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case boolean(Bool)
    case unbound

    var isTruthy: Bool {
        switch self {
        case .boolean(let v): return v
        case .integer(let v): return v != 0
        case .double(let v): return v != 0
        case .string(let v): return !v.isEmpty
        case .unbound: return false
        }
    }

    var stringValue: String {
        switch self {
        case .string(let v): return v
        case .integer(let v): return "\(v)"
        case .double(let v):
            if v == v.rounded() && !v.isInfinite {
                return "\(Int64(v))"
            }
            return "\(v)"
        case .boolean(let v): return v ? "true" : "false"
        case .unbound: return ""
        }
    }

    var plainStringValue: String {
        let raw = stringValue
        // Strip literal quotes
        if raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 {
            let start = raw.index(after: raw.startIndex)
            let end = raw.index(before: raw.endIndex)
            return String(raw[start..<end])
        }
        if raw.hasPrefix("\""), let quoteEnd = raw.dropFirst().firstIndex(of: "\"") {
            return String(raw[raw.index(after: raw.startIndex)..<quoteEnd])
        }
        return raw
    }

    var numericValue: Double? {
        switch self {
        case .integer(let v): return Double(v)
        case .double(let v): return v
        case .string(let v): return Double(v)
        case .boolean(let v): return v ? 1 : 0
        case .unbound: return nil
        }
    }

    static func fromRawValue(_ raw: String) -> FilterValue {
        // リテラル形式 "value" or "value"^^type
        if raw.hasPrefix("\"") {
            // Extract plain value
            if let endQuote = raw.dropFirst().firstIndex(of: "\"") {
                let value = String(raw[raw.index(after: raw.startIndex)..<endQuote])
                if let n = Int64(value) { return .integer(n) }
                if let d = Double(value) { return .double(d) }
                return .string(raw)
            }
            return .string(raw)
        }
        // IRI or prefixed name
        return .string(raw)
    }

    func compareEqual(to other: FilterValue) -> Bool {
        switch (self, other) {
        case (.integer(let a), .integer(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.integer(let a), .double(let b)): return Double(a) == b
        case (.double(let a), .integer(let b)): return a == Double(b)
        case (.boolean(let a), .boolean(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.unbound, .unbound): return true
        default: return stringValue == other.stringValue
        }
    }

    func compareLessThan(_ other: FilterValue) -> Bool {
        switch (self, other) {
        case (.integer(let a), .integer(let b)): return a < b
        case (.double(let a), .double(let b)): return a < b
        case (.integer(let a), .double(let b)): return Double(a) < b
        case (.double(let a), .integer(let b)): return a < Double(b)
        case (.string(let a), .string(let b)): return a < b
        default: return stringValue < other.stringValue
        }
    }

    func add(_ other: FilterValue) -> FilterValue {
        switch (self, other) {
        case (.integer(let a), .integer(let b)): return .integer(a + b)
        case (.double(let a), .double(let b)): return .double(a + b)
        case (.integer(let a), .double(let b)): return .double(Double(a) + b)
        case (.double(let a), .integer(let b)): return .double(a + Double(b))
        default: return .string(stringValue + other.stringValue)
        }
    }

    func subtract(_ other: FilterValue) -> FilterValue {
        switch (self, other) {
        case (.integer(let a), .integer(let b)): return .integer(a - b)
        case (.double(let a), .double(let b)): return .double(a - b)
        case (.integer(let a), .double(let b)): return .double(Double(a) - b)
        case (.double(let a), .integer(let b)): return .double(a - Double(b))
        default: return .double(0)
        }
    }

    func multiply(_ other: FilterValue) -> FilterValue {
        switch (self, other) {
        case (.integer(let a), .integer(let b)): return .integer(a * b)
        case (.double(let a), .double(let b)): return .double(a * b)
        case (.integer(let a), .double(let b)): return .double(Double(a) * b)
        case (.double(let a), .integer(let b)): return .double(a * Double(b))
        default: return .double(0)
        }
    }

    func divide(_ other: FilterValue) throws -> FilterValue {
        guard let denom = other.numericValue, denom != 0 else {
            throw SPARQLEvaluatorError.divisionByZero
        }
        guard let numer = self.numericValue else {
            return .double(0)
        }
        return .double(numer / denom)
    }
}
