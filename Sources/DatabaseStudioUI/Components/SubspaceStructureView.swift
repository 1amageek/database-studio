import SwiftUI
import Core

/// Subspace構造を可視化
public struct SubspaceStructureView: View {
    let structure: SubspaceStructure

    public init(structure: SubspaceStructure) {
        self.structure = structure
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(displayName, systemImage: symbolName)
                .font(.subheadline)
                .fontWeight(.medium)

            structureVisualization
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var displayName: String {
        switch structure {
        case .flat: return "Flat"
        case .hierarchical: return "Hierarchical"
        case .aggregation: return "Aggregation"
        }
    }

    private var symbolName: String {
        switch structure {
        case .flat: return "list.bullet"
        case .hierarchical: return "list.bullet.indent"
        case .aggregation: return "chart.bar"
        }
    }

    @ViewBuilder
    private var structureVisualization: some View {
        switch structure {
        case .flat:
            flatStructure
        case .hierarchical:
            hierarchicalStructure
        case .aggregation:
            aggregationStructure
        }
    }

    private var flatStructure: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("[indexSubspace]")
            Text("  └─ [value1]")
            Text("      └─ [value2]")
            Text("          └─ [primaryKey] = ''")
        }
    }

    private var hierarchicalStructure: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("[indexSubspace]")
            Text("  ├─ [metadata]")
            Text("  ├─ [layers]")
            Text("  │   ├─ [0] → [nodeID] = data")
            Text("  │   └─ [1] → [nodeID] = data")
            Text("  └─ [data]")
            Text("      └─ [key] = value")
        }
    }

    private var aggregationStructure: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("[indexSubspace]")
            Text("  └─ [groupKey] = aggregatedValue")
        }
    }
}

// MARK: - Previews

#Preview("Subspace Structures") {
    VStack(alignment: .leading, spacing: 20) {
        SubspaceStructureView(structure: .flat)
        Divider()
        SubspaceStructureView(structure: .hierarchical)
        Divider()
        SubspaceStructureView(structure: .aggregation)
    }
    .padding()
    .frame(width: 400)
}
