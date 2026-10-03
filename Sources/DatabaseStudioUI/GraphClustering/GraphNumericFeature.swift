import Foundation

struct GraphNumericFeature: Identifiable, Equatable, Sendable {
    enum Transform: String, CaseIterable, Sendable {
        case identity = "Linear", logarithm = "Log10", signedLogarithm = "Asinh"
    }

    var numerator: String
    var denominator: String?
    var transform: Transform = .identity
    var weight: Double = 1
    var id: String { "\(numerator.count):\(numerator)|\(denominator ?? "")" }
    var title: String { denominator.map { numerator + " / " + $0 } ?? numerator }
    var axisTitle: String { title + " · " + transform.rawValue + " · robust units" }

    func value(in node: GraphNode) -> Double? {
        guard let numerator = node.metrics[numerator], numerator.isFinite else { return nil }
        guard let denominator else { return numerator }
        guard let divisor = node.metrics[denominator], divisor.isFinite, divisor > 0 else { return nil }
        let value = numerator / divisor
        return value.isFinite ? value : nil
    }

    func transformed(_ value: Double) -> Double? {
        let result: Double
        switch transform {
        case .identity: result = value
        case .logarithm:
            guard value > 0 else { return nil }
            result = log10(value)
        case .signedLogarithm: result = asinh(value)
        }
        return result.isFinite ? result : nil
    }
}
