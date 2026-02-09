import Foundation
import Synchronization

/// スロークエリログエントリ
public struct SlowQueryEntry: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let queryDescription: String
    public let typeName: String?
    public let executionTime: TimeInterval
    public let operationType: OperationType

    public enum OperationType: String, Sendable {
        case read
        case write
        case scan
        case transaction
    }

    public var executionTimeMs: Double {
        executionTime * 1000
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        queryDescription: String,
        typeName: String? = nil,
        executionTime: TimeInterval,
        operationType: OperationType = .transaction
    ) {
        self.id = id
        self.timestamp = timestamp
        self.queryDescription = queryDescription
        self.typeName = typeName
        self.executionTime = executionTime
        self.operationType = operationType
    }
}

/// データベースメトリクス
public struct DatabaseMetrics: Sendable {
    public let timestamp: Date
    public let totalOperations: Int64
    public let successfulOperations: Int64
    public let latencyP50: TimeInterval
    public let latencyP99: TimeInterval
    public let operationsPerSecond: Double

    public var successRate: Double {
        guard totalOperations > 0 else { return 0 }
        return Double(successfulOperations) / Double(totalOperations)
    }

    public var latencyP50Ms: Double {
        latencyP50 * 1000
    }

    public var latencyP99Ms: Double {
        latencyP99 * 1000
    }

    public init(
        timestamp: Date = Date(),
        totalOperations: Int64,
        successfulOperations: Int64,
        latencyP50: TimeInterval,
        latencyP99: TimeInterval,
        operationsPerSecond: Double
    ) {
        self.timestamp = timestamp
        self.totalOperations = totalOperations
        self.successfulOperations = successfulOperations
        self.latencyP50 = latencyP50
        self.latencyP99 = latencyP99
        self.operationsPerSecond = operationsPerSecond
    }
}

/// メトリクス収集サービス
public final class MetricsService: Sendable {

    private let slowQueryThreshold: Mutex<TimeInterval?>
    private let maxSlowQueries: Int
    private let maxLatencySamples: Int
    private let opsWindow: TimeInterval

    private let slowQueries: Mutex<[SlowQueryEntry]>
    private let latencySamples: Mutex<LatencySampleState>
    private let counters: Mutex<OperationCounters>
    private let operationTimestamps: Mutex<[Date]>

    private struct LatencySampleState: Sendable {
        var samples: [TimeInterval] = []
        var totalCount: Int = 0
    }

    private struct OperationCounters: Sendable {
        var total: Int64 = 0
        var successful: Int64 = 0
    }

    public init(
        maxSlowQueries: Int = 100,
        maxLatencySamples: Int = 1000,
        opsWindow: TimeInterval = 60
    ) {
        self.maxSlowQueries = maxSlowQueries
        self.maxLatencySamples = maxLatencySamples
        self.opsWindow = opsWindow

        self.slowQueryThreshold = Mutex(nil)
        self.slowQueries = Mutex([])
        self.latencySamples = Mutex(LatencySampleState())
        self.counters = Mutex(OperationCounters())
        self.operationTimestamps = Mutex([])
    }

    public func enableSlowQueryLog(threshold: TimeInterval) {
        slowQueryThreshold.withLock { $0 = threshold }
    }

    public func disableSlowQueryLog() {
        slowQueryThreshold.withLock { $0 = nil }
    }

    public var currentThreshold: TimeInterval? {
        slowQueryThreshold.withLock { $0 }
    }

    public var isSlowQueryLogEnabled: Bool {
        currentThreshold != nil
    }

    public func getSlowQueries(limit: Int) -> [SlowQueryEntry] {
        slowQueries.withLock { queries in
            Array(queries.suffix(limit).reversed())
        }
    }

    public func clearSlowQueries() {
        slowQueries.withLock { $0.removeAll() }
    }

    public var slowQueryCount: Int {
        slowQueries.withLock { $0.count }
    }

    public func currentMetrics() -> DatabaseMetrics {
        let currentCounters = counters.withLock { $0 }
        let (p50, p99) = calculatePercentiles()
        let ops = calculateOPS()

        return DatabaseMetrics(
            totalOperations: currentCounters.total,
            successfulOperations: currentCounters.successful,
            latencyP50: p50,
            latencyP99: p99,
            operationsPerSecond: ops
        )
    }

    public func reset() {
        slowQueries.withLock { $0.removeAll() }
        latencySamples.withLock { $0 = LatencySampleState() }
        counters.withLock { $0 = OperationCounters() }
        operationTimestamps.withLock { $0.removeAll() }
    }

    @discardableResult
    public func measure<T: Sendable>(
        description: String,
        typeName: String? = nil,
        operationType: SlowQueryEntry.OperationType = .transaction,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let result = try await operation()
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            recordSuccess(duration: duration, description: description, typeName: typeName, operationType: operationType)
            return result
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            recordFailure(duration: duration, description: description, typeName: typeName, operationType: operationType)
            throw error
        }
    }

    public func recordSuccess(
        duration: TimeInterval,
        description: String,
        typeName: String? = nil,
        operationType: SlowQueryEntry.OperationType = .transaction
    ) {
        counters.withLock { counters in
            counters.total += 1
            counters.successful += 1
        }
        recordLatency(duration)
        recordOperationTimestamp()
        checkSlowQuery(duration: duration, description: description, typeName: typeName, operationType: operationType)
    }

    public func recordFailure(
        duration: TimeInterval,
        description: String,
        typeName: String? = nil,
        operationType: SlowQueryEntry.OperationType = .transaction
    ) {
        counters.withLock { counters in
            counters.total += 1
        }
        recordLatency(duration)
        recordOperationTimestamp()
        checkSlowQuery(duration: duration, description: "[FAILED] \(description)", typeName: typeName, operationType: operationType)
    }

    private func recordLatency(_ duration: TimeInterval) {
        latencySamples.withLock { state in
            state.totalCount += 1
            if state.samples.count < maxLatencySamples {
                state.samples.append(duration)
            } else {
                let index = Int.random(in: 0..<state.totalCount)
                if index < maxLatencySamples {
                    state.samples[index] = duration
                }
            }
        }
    }

    private func recordOperationTimestamp() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-opsWindow)
        operationTimestamps.withLock { timestamps in
            timestamps.removeAll { $0 < cutoff }
            timestamps.append(now)
        }
    }

    private func checkSlowQuery(
        duration: TimeInterval,
        description: String,
        typeName: String?,
        operationType: SlowQueryEntry.OperationType
    ) {
        guard let threshold = slowQueryThreshold.withLock({ $0 }) else { return }
        guard duration >= threshold else { return }

        let entry = SlowQueryEntry(
            queryDescription: description,
            typeName: typeName,
            executionTime: duration,
            operationType: operationType
        )

        slowQueries.withLock { queries in
            queries.append(entry)
            if queries.count > maxSlowQueries {
                queries.removeFirst(queries.count - maxSlowQueries)
            }
        }
    }

    private func calculatePercentiles() -> (p50: TimeInterval, p99: TimeInterval) {
        let samples = latencySamples.withLock { $0.samples }
        guard !samples.isEmpty else { return (0, 0) }
        let sorted = samples.sorted()
        let count = sorted.count
        let p50Index = Int(Double(count) * 0.50)
        let p99Index = min(Int(Double(count) * 0.99), count - 1)
        return (sorted[p50Index], sorted[p99Index])
    }

    private func calculateOPS() -> Double {
        let timestamps = operationTimestamps.withLock { $0 }
        guard !timestamps.isEmpty else { return 0 }
        let now = Date()
        let cutoff = now.addingTimeInterval(-opsWindow)
        let recentCount = timestamps.filter { $0 >= cutoff }.count
        return Double(recentCount) / opsWindow
    }
}
