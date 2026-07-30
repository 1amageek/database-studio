import SwiftUI
import Observation

/// Owns monitoring state displayed by the metrics dashboard.
@MainActor
@Observable
public final class MetricsDashboardState {
    // MARK: - State

    public private(set) var metrics: DatabaseMetrics?
    public private(set) var slowQueries: [SlowQueryEntry] = []

    public var slowQueryThreshold: TimeInterval = 0.1 {
        didSet {
            if isMonitoring {
                metricsRecorder.enableSlowQueryLog(threshold: slowQueryThreshold)
            }
        }
    }

    public private(set) var isMonitoring: Bool = false

    // MARK: - Configuration

    public var refreshInterval: TimeInterval = 5.0
    public var slowQueryLimit: Int = 20

    // MARK: - Private

    @ObservationIgnored
    private let metricsRecorder: DatabaseMetricsRecorder

    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(metricsRecorder: DatabaseMetricsRecorder) {
        self.metricsRecorder = metricsRecorder
    }

    // MARK: - Monitoring Control

    public func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        metricsRecorder.enableSlowQueryLog(threshold: slowQueryThreshold)

        refreshMetrics()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self?.refreshInterval ?? 5.0))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                self?.refreshMetrics()
            }
        }
    }

    public func stopMonitoring() {
        isMonitoring = false
        metricsRecorder.disableSlowQueryLog()
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
        metrics = metricsRecorder.metricsSnapshot()
        slowQueries = metricsRecorder.slowQueries(limit: slowQueryLimit)
    }

    public func clearSlowQueries() {
        metricsRecorder.clearSlowQueries()
        slowQueries = []
    }

    public func resetMetrics() {
        metricsRecorder.reset()
        metrics = nil
        slowQueries = []
    }

    // MARK: - Cleanup

    deinit {
        refreshTask?.cancel()
    }
}

// MARK: - Preview Support

extension MetricsDashboardState {
    public static var preview: MetricsDashboardState {
        let metricsRecorder = DatabaseMetricsRecorder()
        let dashboardState = MetricsDashboardState(metricsRecorder: metricsRecorder)

        metricsRecorder.enableSlowQueryLog(threshold: 0.1)

        metricsRecorder.recordSuccess(duration: 0.05, description: "Fetch users")
        metricsRecorder.recordSuccess(duration: 0.02, description: "Fetch posts")
        metricsRecorder.recordSuccess(duration: 0.15, description: "Complex query", typeName: "User")
        metricsRecorder.recordSuccess(duration: 0.25, description: "Full scan", typeName: "Post")
        metricsRecorder.recordFailure(duration: 0.30, description: "Timeout query", typeName: "Comment")

        dashboardState.refreshMetrics()
        return dashboardState
    }
}
