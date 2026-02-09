import SwiftUI

/// メトリクスダッシュボードビュー
public struct MetricsDashboardView: View {
    @Bindable public var viewModel: MetricsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: MetricsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // モニタリングコントロール
                    monitoringControls

                    // メトリクスグリッド
                    if let metrics = viewModel.metrics {
                        metricsGridView(metrics: metrics)
                    } else {
                        emptyMetricsView
                    }

                    Divider()

                    // スロークエリログ
                    slowQuerySection
                }
                .padding()
            }
            .navigationTitle("Performance Metrics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 500)
    }

    // MARK: - Monitoring Controls

    @ViewBuilder
    private var monitoringControls: some View {
        HStack(spacing: 12) {
            // 閾値設定
            HStack {
                Text("Threshold:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("ms", value: Binding(
                    get: { viewModel.slowQueryThreshold * 1000 },
                    set: { viewModel.slowQueryThreshold = $0 / 1000 }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                Text("ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // トグルボタン
            Button(action: viewModel.toggleMonitoring) {
                HStack {
                    Image(systemName: viewModel.isMonitoring ? "stop.fill" : "play.fill")
                    Text(viewModel.isMonitoring ? "Stop" : "Start")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isMonitoring ? .red : .accentColor)
        }
    }

    // MARK: - Metrics Grid

    @ViewBuilder
    private func metricsGridView(metrics: DatabaseMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Metrics")
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                metricCard(
                    title: "Operations",
                    value: "\(metrics.totalOperations)",
                    subtitle: "\(String(format: "%.1f%%", metrics.successRate * 100)) success",
                    icon: "number.circle.fill",
                    color: .blue
                )

                metricCard(
                    title: "P50 Latency",
                    value: String(format: "%.2f ms", metrics.latencyP50Ms),
                    subtitle: "Median response time",
                    icon: "gauge.medium",
                    color: .green
                )

                metricCard(
                    title: "P99 Latency",
                    value: String(format: "%.2f ms", metrics.latencyP99Ms),
                    subtitle: "99th percentile",
                    icon: "gauge.high",
                    color: latencyColor(metrics.latencyP99Ms)
                )

                metricCard(
                    title: "OPS",
                    value: String(format: "%.1f", metrics.operationsPerSecond),
                    subtitle: "Operations per second",
                    icon: "speedometer",
                    color: .purple
                )
            }
        }
    }

    @ViewBuilder
    private func metricCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.bold)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < 50 { return .green }
        if ms < 200 { return .yellow }
        return .red
    }

    @ViewBuilder
    private var emptyMetricsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No metrics data")
                .font(.headline)
            Text("Start monitoring to collect performance metrics")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Slow Query Section

    @ViewBuilder
    private var slowQuerySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Slow Queries")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if !viewModel.slowQueries.isEmpty {
                    Button("Clear") {
                        viewModel.clearSlowQueries()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            if viewModel.slowQueries.isEmpty {
                emptySlowQueryView
            } else {
                SlowQueryLogView(queries: viewModel.slowQueries)
            }
        }
    }

    @ViewBuilder
    private var emptySlowQueryView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("No slow queries detected")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

#Preview {
    MetricsDashboardView(viewModel: .preview)
}
