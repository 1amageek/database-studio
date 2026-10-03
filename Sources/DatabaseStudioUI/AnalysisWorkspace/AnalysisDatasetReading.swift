import Foundation

protocol AnalysisDatasetReading: Sendable {
    func read(url: URL) async throws -> AnalysisDataset
}
