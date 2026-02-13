import SwiftUI

/// ファセットフィルターの値を編集するポップオーバー
struct GraphFilterEditorPopover: View {
    @State var token: GraphFilterToken
    let state: GraphViewState
    var onUpdate: (GraphFilterToken) -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(token.facet.categoryLabel)
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Mode toggle
            Picker("Mode", selection: $token.mode) {
                Text("Include").tag(GraphFilterMode.include)
                Text("Exclude").tag(GraphFilterMode.exclude)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Facet-specific editor
            facetEditor
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: 280)
        .onChange(of: token) { _, newValue in
            onUpdate(newValue)
        }
    }

    // MARK: - Facet Editor

    @ViewBuilder
    private var facetEditor: some View {
        switch token.facet {
        case .nodeRole:
            nodeRoleEditor
        case .nodeType:
            nodeTypeEditor
        case .nodeSource:
            nodeSourceEditor
        case .edgeKind:
            edgeKindEditor
        case .edgeLabel:
            edgeLabelEditor
        case .community:
            communityEditor
        case .metricThreshold:
            metricThresholdEditor
        case .metadataContains:
            metadataEditor
        }
    }

    // MARK: - Node Role Editor

    private var currentRoles: Set<GraphNodeRole> {
        if case .nodeRole(let s) = token.facet { return s }
        return Set(GraphNodeRole.allCases)
    }

    @ViewBuilder
    private var nodeRoleEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(GraphNodeRole.allCases, id: \.self) { role in
                Toggle(isOn: Binding(
                    get: { currentRoles.contains(role) },
                    set: { isOn in
                        var roles = currentRoles
                        if isOn { roles.insert(role) } else { roles.remove(role) }
                        token.facet = .nodeRole(roles)
                    }
                )) {
                    Text(role.displayName)
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: - Node Type Editor

    private var currentTypes: Set<String> {
        if case .nodeType(let s) = token.facet { return s }
        return []
    }

    @ViewBuilder
    private var nodeTypeEditor: some View {
        let availableTypes = state.availableIndividualTypes

        if availableTypes.isEmpty {
            Text("No types available")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(availableTypes, id: \.id) { type in
                        Toggle(isOn: Binding(
                            get: { currentTypes.contains(type.id) },
                            set: { isOn in
                                var types = currentTypes
                                if isOn { types.insert(type.id) } else { types.remove(type.id) }
                                token.facet = .nodeType(types)
                            }
                        )) {
                            Text(type.label)
                                .font(.callout)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    // MARK: - Node Source Editor

    private var currentSources: Set<GraphNodeSource> {
        if case .nodeSource(let s) = token.facet { return s }
        return Set(GraphNodeSource.allCases)
    }

    @ViewBuilder
    private var nodeSourceEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(GraphNodeSource.allCases, id: \.self) { source in
                Toggle(isOn: Binding(
                    get: { currentSources.contains(source) },
                    set: { isOn in
                        var sources = currentSources
                        if isOn { sources.insert(source) } else { sources.remove(source) }
                        token.facet = .nodeSource(sources)
                    }
                )) {
                    Text(source.rawValue)
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: - Edge Kind Editor

    private var currentKinds: Set<GraphEdgeKind> {
        if case .edgeKind(let s) = token.facet { return s }
        return Set(GraphEdgeKind.allCases)
    }

    @ViewBuilder
    private var edgeKindEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(GraphEdgeKind.allCases, id: \.self) { kind in
                Toggle(isOn: Binding(
                    get: { currentKinds.contains(kind) },
                    set: { isOn in
                        var kinds = currentKinds
                        if isOn { kinds.insert(kind) } else { kinds.remove(kind) }
                        token.facet = .edgeKind(kinds)
                    }
                )) {
                    Text(kind.rawValue)
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: - Edge Label Editor

    private var currentEdgeLabels: Set<String> {
        if case .edgeLabel(let s) = token.facet { return s }
        return []
    }

    @ViewBuilder
    private var edgeLabelEditor: some View {
        let allLabels = state.allEdgeLabels

        if allLabels.isEmpty {
            Text("No edge labels available")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allLabels, id: \.self) { label in
                        Toggle(isOn: Binding(
                            get: { currentEdgeLabels.contains(label) },
                            set: { isOn in
                                var labels = currentEdgeLabels
                                if isOn { labels.insert(label) } else { labels.remove(label) }
                                token.facet = .edgeLabel(labels)
                            }
                        )) {
                            HStack {
                                Text(label)
                                    .font(.callout)
                                Spacer()
                                Text("\(state.edgeCount(for: label))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    // MARK: - Community Editor

    private var currentCommunityIDs: Set<Int> {
        if case .community(let s) = token.facet { return s }
        return []
    }

    @ViewBuilder
    private var communityEditor: some View {
        let availableIDs = state.availableCommunityIDs

        if availableIDs.isEmpty {
            Text("No communities detected")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(availableIDs, id: \.self) { cid in
                        Toggle(isOn: Binding(
                            get: { currentCommunityIDs.contains(cid) },
                            set: { isOn in
                                var ids = currentCommunityIDs
                                if isOn { ids.insert(cid) } else { ids.remove(cid) }
                                token.facet = .community(ids)
                            }
                        )) {
                            HStack {
                                let count = GraphVisualMapping.communityPalette.count
                                Circle()
                                    .fill(GraphVisualMapping.communityPalette[((cid % count) + count) % count])
                                    .frame(width: 10, height: 10)
                                Text("Community \(cid)")
                                    .font(.callout)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    // MARK: - Metric Threshold Editor

    private var currentMetric: String {
        if case .metricThreshold(let m, _, _) = token.facet { return m }
        return "pageRank"
    }

    private var currentOp: GraphFilterComparisonOp {
        if case .metricThreshold(_, let op, _) = token.facet { return op }
        return .greaterThan
    }

    private var currentThresholdValue: Double {
        if case .metricThreshold(_, _, let v) = token.facet { return v }
        return 0.0
    }

    @ViewBuilder
    private var metricThresholdEditor: some View {
        let availableMetrics = state.availableMetricKeys

        VStack(alignment: .leading, spacing: 8) {
            if availableMetrics.isEmpty {
                Text("No metrics available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Metric", selection: Binding(
                    get: { currentMetric },
                    set: { token.facet = .metricThreshold(metric: $0, op: currentOp, value: currentThresholdValue) }
                )) {
                    ForEach(availableMetrics, id: \.self) { key in
                        Text(key).tag(key)
                    }
                }

                Picker("Operator", selection: Binding(
                    get: { currentOp },
                    set: { token.facet = .metricThreshold(metric: currentMetric, op: $0, value: currentThresholdValue) }
                )) {
                    ForEach(GraphFilterComparisonOp.allCases, id: \.self) { op in
                        Text(op.rawValue).tag(op)
                    }
                }

                HStack {
                    Text("Value")
                        .font(.callout)
                    TextField("0.0", value: Binding(
                        get: { currentThresholdValue },
                        set: { token.facet = .metricThreshold(metric: currentMetric, op: currentOp, value: $0) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                }
            }
        }
    }

    // MARK: - Metadata Editor

    private var currentMetadataKey: String? {
        if case .metadataContains(let k, _) = token.facet { return k }
        return nil
    }

    private var currentMetadataValue: String {
        if case .metadataContains(_, let v) = token.facet { return v }
        return ""
    }

    @ViewBuilder
    private var metadataEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Key")
                    .font(.callout)
                    .frame(width: 40, alignment: .leading)
                TextField("(all keys)", text: Binding(
                    get: { currentMetadataKey ?? "" },
                    set: { newKey in
                        let key = newKey.isEmpty ? nil : newKey
                        token.facet = .metadataContains(key: key, value: currentMetadataValue)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Value")
                    .font(.callout)
                    .frame(width: 40, alignment: .leading)
                TextField("Search text", text: Binding(
                    get: { currentMetadataValue },
                    set: { newValue in
                        token.facet = .metadataContains(key: currentMetadataKey, value: newValue)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
    }
}
