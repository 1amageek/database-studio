import SwiftUI

/// イベントタイムラインビュー（Inspector の Events タブ）
struct EventTimelineView: View {
    let events: [(node: GraphNode, date: Date?, role: String)]
    let allEdges: [GraphEdge]
    let allNodes: [GraphNode]

    @Environment(\.openWindow) private var openWindow
    @State private var expandedEventID: String?

    /// 折りたたみ表示で非表示にするエッジラベル（ノイズ）
    private static let noiseEdgeLabels: Set<String> = [
        "type", "rdf:type", "a",
        "hasParticipant", "participant",
        "label", "rdfs:label",
        "comment", "rdfs:comment"
    ]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        if events.isEmpty {
            ContentUnavailableView(
                "No Events",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("No events are connected to this node")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(events.enumerated()), id: \.element.node.id) { _, event in
                    eventItem(event: event)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func eventItem(event: (node: GraphNode, date: Date?, role: String)) -> some View {
        let isExpanded = expandedEventID == event.node.id

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedEventID = isExpanded ? nil : event.node.id
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 2) {
                        // メタデータの label を優先表示
                        let displayLabel = event.node.metadata["label"] ?? event.node.metadata["name"] ?? event.node.label
                        Text(displayLabel)
                            .font(.callout.weight(.medium))
                            .lineLimit(2)

                        // displayLabel と異なる場合にIRI名を補足表示
                        if displayLabel != event.node.label {
                            Text(event.node.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let summary = eventSummary(for: event.node) {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        if let date = event.date {
                            Text(Self.dateFormatter.string(from: date))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                eventDetail(node: event.node)
                    .padding(.leading, 18)
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func eventDetail(node: GraphNode) -> some View {
        let outgoing = allEdges.filter { $0.sourceID == node.id }
        let incoming = allEdges.filter { $0.targetID == node.id }

        VStack(alignment: .leading, spacing: 6) {
            // メタデータ（日付等の属性）
            let metadata = node.metadata.sorted(by: { $0.key < $1.key })
            if !metadata.isEmpty {
                ForEach(metadata, id: \.key) { key, value in
                    HStack(alignment: .top, spacing: 6) {
                        Text(key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text(value)
                            .font(.caption)
                            .lineLimit(3)
                    }
                }
            }

            // 関連エンティティ（Outgoing: event → target）
            if !outgoing.isEmpty {
                Divider().padding(.vertical, 2)

                ForEach(outgoing) { edge in
                    HStack(alignment: .top, spacing: 6) {
                        Text(edge.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text(nodeLabel(for: edge.targetID))
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }

            // 関連エンティティ（Incoming: source → event）
            if !incoming.isEmpty {
                if outgoing.isEmpty {
                    Divider().padding(.vertical, 2)
                }

                ForEach(incoming) { edge in
                    HStack(alignment: .top, spacing: 6) {
                        Text(edge.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text(nodeLabel(for: edge.sourceID))
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }

            // 別ウィンドウでグラフ表示
            Button {
                let eventState = EventGraphWindowState.shared
                eventState.document = GraphWindowState.shared.document
                eventState.focusNodeID = node.id
                eventState.entityName = node.label
                openWindow(id: "event-graph")
            } label: {
                Label("Show in Graph", systemImage: "macwindow")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
    }

    /// イベントの核心的な関係を要約テキストとして返す
    private func eventSummary(for node: GraphNode) -> String? {
        let outgoing = allEdges.filter { $0.sourceID == node.id }
        let summaryParts: [String] = outgoing.compactMap { edge in
            let label = localName(edge.label)
            if Self.noiseEdgeLabels.contains(label) { return nil }
            let target = nodeLabel(for: edge.targetID)
            return "\(label): \(target)"
        }
        guard !summaryParts.isEmpty else { return nil }
        return summaryParts.joined(separator: " · ")
    }

    private func nodeLabel(for id: String) -> String {
        allNodes.first { $0.id == id }?.label ?? localName(id)
    }
}
