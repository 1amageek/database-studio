import Foundation

struct GraphAnalysisAxis: Sendable {
    let title: String
    let lower: Double
    let upper: Double

    func coordinate(_ value: Double) -> Double {
        upper > lower ? (value - lower) / (upper - lower) * 8 - 4 : 0
    }

    func value(at coordinate: Double) -> Double {
        lower + (coordinate + 4) / 8 * (upper - lower)
    }
}
