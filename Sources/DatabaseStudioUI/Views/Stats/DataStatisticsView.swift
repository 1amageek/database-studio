import SwiftUI

/// データ統計ダッシュボード
public struct DataStatisticsView: View {
    let viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var typeStats: [TypeStatistics] {
        computeTypeStatistics()
    }

    private var totalItemCount: Int {
        typeStats.reduce(0) { $0 + $1.itemCount }
    }

    private var totalSize: Int64 {
        typeStats.reduce(0) { $0 + $1.totalSize }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summarySection

                    Divider()

                    typeBreakdownSection

                    if !viewModel.discoveredFields.isEmpty {
                        Divider()

                        fieldStatsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Data Statistics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 450, idealWidth: 550, minHeight: 350, idealHeight: 450)
    }

    // MARK: - Summary Section

    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatCard(
                    title: "Total Items",
                    value: formatNumber(totalItemCount),
                    icon: "doc.text.fill",
                    color: .blue
                )

                StatCard(
                    title: "Total Size",
                    value: formatBytes(totalSize),
                    icon: "externaldrive.fill",
                    color: .green
                )

                StatCard(
                    title: "Types",
                    value: "\(typeStats.count)",
                    icon: "folder.fill",
                    color: .orange
                )
            }
        }
    }

    // MARK: - Type Breakdown

    @ViewBuilder
    private var typeBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Types")
                .font(.headline)

            if typeStats.isEmpty {
                emptyStateView("No types found", systemImage: "tray")
            } else {
                VStack(spacing: 8) {
                    ForEach(typeStats.sorted { $0.itemCount > $1.itemCount }) { stat in
                        TypeStatRow(stat: stat, totalCount: totalItemCount)
                    }
                }
            }
        }
    }

    // MARK: - Field Stats

    @ViewBuilder
    private var fieldStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fields (\(viewModel.discoveredFields.count))")
                .font(.headline)

            let groupedFields = Dictionary(grouping: viewModel.discoveredFields) { $0.inferredType }
            let sortedKeys = groupedFields.keys.sorted { $0.rawValue < $1.rawValue }

            ForEach(sortedKeys, id: \.self) { type in
                if let fields = groupedFields[type] {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(fields.sorted { $0.path < $1.path }) { field in
                                HStack {
                                    Text(field.path)
                                        .font(.system(.caption, design: .monospaced))
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.leading)
                    } label: {
                        HStack {
                            Image(systemName: type.iconName)
                                .foregroundStyle(fieldTypeColor(type))
                            Text(fieldTypeDisplayName(type))
                            Spacer()
                            Text("\(fields.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func fieldTypeDisplayName(_ type: DiscoveredField.FieldType) -> String {
        switch type {
        case .string: return "String"
        case .number: return "Number"
        case .boolean: return "Boolean"
        case .object: return "Object"
        case .array: return "Array"
        case .vector: return "Vector"
        case .mixed: return "Mixed"
        case .unknown: return "Unknown"
        }
    }

    private func fieldTypeColor(_ type: DiscoveredField.FieldType) -> Color {
        switch type {
        case .string: return .blue
        case .number: return .green
        case .boolean: return .orange
        case .object: return .purple
        case .array: return .cyan
        case .vector: return .teal
        case .mixed: return .yellow
        case .unknown: return .gray
        }
    }

    // MARK: - Helpers

    private func computeTypeStatistics() -> [TypeStatistics] {
        var stats: [String: TypeStatistics] = [:]

        for item in viewModel.currentItems {
            let typeName = item.typeName
            if var existing = stats[typeName] {
                existing.itemCount += 1
                existing.totalSize += Int64(item.rawSize)
                stats[typeName] = existing
            } else {
                stats[typeName] = TypeStatistics(
                    typeName: typeName,
                    itemCount: 1,
                    totalSize: Int64(item.rawSize)
                )
            }
        }

        return Array(stats.values)
    }

    @ViewBuilder
    private func emptyStateView(_ message: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Types

private struct TypeStatistics: Identifiable {
    let id = UUID()
    var typeName: String
    var itemCount: Int
    var totalSize: Int64

    var avgSize: Int64 {
        itemCount > 0 ? totalSize / Int64(itemCount) : 0
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TypeStatRow: View {
    let stat: TypeStatistics
    let totalCount: Int

    private var percentage: Double {
        totalCount > 0 ? Double(stat.itemCount) / Double(totalCount) : 0
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(stat.typeName)
                    .font(.system(.body, design: .monospaced))

                Spacer()

                Text("\(stat.itemCount)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(formatBytes(stat.totalSize))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 80, alignment: .trailing)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 4)

                    Rectangle()
                        .fill(.blue)
                        .frame(width: geometry.size.width * percentage, height: 4)
                }
                .clipShape(Capsule())
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Preview

#Preview {
    DataStatisticsView(viewModel: AppViewModel.preview(
        items: PreviewData.userItems
    ))
}
