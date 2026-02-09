import SwiftUI

/// ノード詳細 Inspector（Info + Metrics + Edges）
struct GraphInspectorView: View {
    let node: GraphNode
    let incomingEdges: [GraphEdge]
    let outgoingEdges: [GraphEdge]
    let allNodes: [GraphNode]

    var body: some View {
        List {
            // Info
            Section("Info") {
                LabeledContent("IRI", value: node.id)
                LabeledContent("Label", value: node.label)
                LabeledContent("Kind", value: node.kind.displayName)
            }

            // Metadata
            if !node.metadata.isEmpty {
                Section("Metadata") {
                    ForEach(node.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(key, value: value)
                    }
                }
            }

            // Metrics
            if !node.metrics.isEmpty || node.communityID != nil {
                Section("Metrics") {
                    if let communityID = node.communityID {
                        HStack {
                            Text("Community")
                            Spacer()
                            Circle()
                                .fill({
                                let count = GraphVisualMapping.communityPalette.count
                                return GraphVisualMapping.communityPalette[((communityID % count) + count) % count]
                            }())
                                .frame(width: 10, height: 10)
                            Text("\(communityID)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(node.metrics.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(metricDisplayName(key)) {
                            Text(formatMetric(key: key, value: value))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Degree
            if !outgoingEdges.isEmpty || !incomingEdges.isEmpty {
                Section("Degree") {
                    LabeledContent("In-degree", value: "\(incomingEdges.count)")
                    LabeledContent("Out-degree", value: "\(outgoingEdges.count)")
                    LabeledContent("Total", value: "\(incomingEdges.count + outgoingEdges.count)")
                }
            }

            // Outgoing Edges
            if !outgoingEdges.isEmpty {
                Section("Outgoing (\(outgoingEdges.count))") {
                    ForEach(outgoingEdges) { edge in
                        HStack {
                            Text(edge.label)
                                .foregroundStyle(.secondary)
                                .font(.callout)
                            Spacer()
                            Text(nodeLabel(for: edge.targetID))
                                .lineLimit(1)
                        }
                    }
                }
            }

            // Incoming Edges
            if !incomingEdges.isEmpty {
                Section("Incoming (\(incomingEdges.count))") {
                    ForEach(incomingEdges) { edge in
                        HStack {
                            Text(nodeLabel(for: edge.sourceID))
                                .lineLimit(1)
                            Spacer()
                            Text(edge.label)
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Helpers

    private func nodeLabel(for id: String) -> String {
        allNodes.first { $0.id == id }?.label ?? localName(id)
    }

    private func metricDisplayName(_ key: String) -> String {
        switch key {
        case "pageRank": return "PageRank"
        case "degree": return "Degree"
        case "betweenness": return "Betweenness"
        case "closeness": return "Closeness"
        default: return key
        }
    }

    private func formatMetric(key: String, value: Double) -> String {
        switch key {
        case "degree":
            return "\(Int(value))"
        default:
            return String(format: "%.6f", value)
        }
    }
}
