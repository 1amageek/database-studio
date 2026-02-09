import SwiftUI
import Observation

/// メトリクス表示用ViewModel
@MainActor
@Observable
public final class MetricsViewModel {
    // MARK: - State

    public private(set) var metrics: DatabaseMetrics?
    public private(set) var slowQueries: [SlowQueryEntry] = []

    public var slowQueryThreshold: TimeInterval = 0.1 {
        didSet {
            if isMonitoring {
                metricsService.enableSlowQueryLog(threshold: slowQueryThreshold)
            }
        }
    }

    public private(set) var isMonitoring: Bool = false

    // MARK: - Configuration

    public var refreshInterval: TimeInterval = 5.0
    public var slowQueryLimit: Int = 20

    // MARK: - Private

    @ObservationIgnored
    private let metricsService: MetricsService

    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(metricsService: MetricsService) {
        self.metricsService = metricsService
    }

    // MARK: - Monitoring Control

    public func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        metricsService.enableSlowQueryLog(threshold: slowQueryThreshold)

        refreshMetrics()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.refreshInterval ?? 5.0))
                guard !Task.isCancelled else { break }
                self?.refreshMetrics()
            }
        }
    }

    public func stopMonitoring() {
        isMonitoring = false
        metricsService.disableSlowQueryLog()
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    // MARK: - Data Refresh

    public func refreshMetrics() {
        metrics = metricsService.currentMetrics()
        slowQueries = metricsService.getSlowQueries(limit: slowQueryLimit)
    }

    public func clearSlowQueries() {
        metricsService.clearSlowQueries()
        slowQueries = []
    }

    public func resetMetrics() {
        metricsService.reset()
        metrics = nil
        slowQueries = []
    }

    // MARK: - Cleanup

    deinit {
        refreshTask?.cancel()
    }
}

// MARK: - Preview Support

extension MetricsViewModel {
    public static var preview: MetricsViewModel {
        let service = MetricsService()
        let vm = MetricsViewModel(metricsService: service)

        service.enableSlowQueryLog(threshold: 0.1)

        service.recordSuccess(duration: 0.05, description: "Fetch users")
        service.recordSuccess(duration: 0.02, description: "Fetch posts")
        service.recordSuccess(duration: 0.15, description: "Complex query", typeName: "User")
        service.recordSuccess(duration: 0.25, description: "Full scan", typeName: "Post")
        service.recordFailure(duration: 0.30, description: "Timeout query", typeName: "Comment")

        vm.refreshMetrics()
        return vm
    }
}
