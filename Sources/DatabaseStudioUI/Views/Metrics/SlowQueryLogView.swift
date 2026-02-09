import SwiftUI

/// スロークエリログ表示ビュー
public struct SlowQueryLogView: View {
    public let queries: [SlowQueryEntry]

    public init(queries: [SlowQueryEntry]) {
        self.queries = queries
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ヘッダー行
            headerRow
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.3))

            Divider()

            // クエリ一覧
            ForEach(queries) { query in
                queryRow(query)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                if query.id != queries.last?.id {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .background(.quaternary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Time")
                .frame(width: 80, alignment: .leading)
            Text("Duration")
                .frame(width: 80, alignment: .trailing)
            Text("Type")
                .frame(width: 60, alignment: .leading)
            Text("Description")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func queryRow(_ query: SlowQueryEntry) -> some View {
        HStack(spacing: 12) {
            Text(formatTime(query.timestamp))
                .frame(width: 80, alignment: .leading)
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                Text(String(format: "%.2f", query.executionTimeMs))
                    .fontWeight(.medium)
                    .foregroundStyle(latencyColor(query.executionTimeMs))
                Text("ms")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .trailing)

            operationTypeBadge(query.operationType)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(query.queryDescription)
                    .lineLimit(1)
                if let typeName = query.typeName {
                    Text(typeName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
    }

    @ViewBuilder
    private func operationTypeBadge(_ type: SlowQueryEntry.OperationType) -> some View {
        Text(type.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(operationColor(type).opacity(0.2))
            .foregroundStyle(operationColor(type))
            .clipShape(Capsule())
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < 100 { return .yellow }
        if ms < 500 { return .orange }
        return .red
    }

    private func operationColor(_ type: SlowQueryEntry.OperationType) -> Color {
        switch type {
        case .read:
            return .blue
        case .write:
            return .green
        case .scan:
            return .purple
        case .transaction:
            return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    SlowQueryLogView(queries: [
        SlowQueryEntry(
            timestamp: Date(),
            queryDescription: "Fetch users with complex filter",
            typeName: "User",
            executionTime: 0.15,
            operationType: .read
        ),
        SlowQueryEntry(
            timestamp: Date().addingTimeInterval(-30),
            queryDescription: "Full table scan",
            typeName: "Post",
            executionTime: 0.45,
            operationType: .scan
        ),
        SlowQueryEntry(
            timestamp: Date().addingTimeInterval(-60),
            queryDescription: "Batch insert",
            typeName: "Comment",
            executionTime: 0.22,
            operationType: .write
        ),
        SlowQueryEntry(
            timestamp: Date().addingTimeInterval(-120),
            queryDescription: "[FAILED] Connection timeout",
            typeName: nil,
            executionTime: 5.0,
            operationType: .transaction
        )
    ])
    .padding()
    .frame(width: 600)
}
