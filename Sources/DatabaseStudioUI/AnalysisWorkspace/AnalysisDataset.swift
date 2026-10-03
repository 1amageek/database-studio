import Foundation

struct AnalysisDataset: Sendable {
    let document: GraphDocument
    let sourceName: String
    let provenance: [String]
    let warnings: [String]
    let numericColumns: [String]
    let missingCounts: [String: Int]
}
