import Foundation
import Observation

@Observable @MainActor
final class GraphClusterSession {
    var configuration = GraphClusterConfiguration() { didSet { if configuration != oldValue { invalidate() } } }
    private(set) var result: GraphClusterResult?
    private(set) var failure: String?
    private(set) var isLoading = false
    private(set) var revision: UInt64 = 0
    var selectedCluster: Int?
    var cameraScale: CGFloat = 1
    var cameraOffset = CGSize.zero
    private(set) var coordinateCenter = SIMD2<Double>.zero
    private(set) var coordinateExtent = SIMD2<Double>(repeating: 12)
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    private let analyzer: any GraphClusterAnalyzing

    init(analyzer: any GraphClusterAnalyzing = GraphFeatureAnalyzer()) { self.analyzer = analyzer }

    var emphasizedIDs: Set<String> {
        guard let selectedCluster, let result, let cluster = result.clusters.first(where: { $0.id == selectedCluster }) else { return [] }
        return Set(cluster.members)
    }

    func invalidate() {
        cancel(); result = nil; failure = nil; selectedCluster = nil
        cameraOffset = .zero; cameraScale = 1; revision &+= 1
    }

    func cancel() {
        generation &+= 1; task?.cancel(); task = nil; isLoading = false
    }

    func prepare(document: GraphDocument) async {
        if result != nil || failure != nil { return }
        if let task { await task.value; return }
        generation &+= 1
        let current = generation, configuration = configuration, analyzer = analyzer
        isLoading = true
        let operation = Task { [weak self] in
            do {
                let result = try await analyzer.analyze(document: document, configuration: configuration)
                guard let self, self.generation == current, !Task.isCancelled else { return }
                self.result = result; self.isLoading = false; self.task = nil
                var lower = SIMD2<Double>(repeating: .infinity), upper = SIMD2<Double>(repeating: -.infinity)
                for id in Set(result.membership.keys).union(result.unassignedIDs) {
                    if let point = result.positions[id] {
                        lower = SIMD2(min(lower.x, point.x), min(lower.y, point.y))
                        upper = SIMD2(max(upper.x, point.x), max(upper.y, point.y))
                    }
                }
                self.coordinateCenter = (lower + upper) / 2
                self.coordinateExtent = upper - lower + SIMD2(repeating: 2)
            } catch is CancellationError {
                guard let self, self.generation == current else { return }
                self.isLoading = false; self.task = nil
            } catch {
                guard let self, self.generation == current else { return }
                self.failure = error.localizedDescription; self.isLoading = false; self.task = nil
            }
        }
        task = operation
        await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
    }
}
