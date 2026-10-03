import SwiftUI

struct GraphClusterControls: View {
    @Bindable var state: GraphViewState
    @State private var showFeatures = false
    @State private var showMembers = false

    var body: some View {
        @Bindable var session = state.clusterSession
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button("Features…", systemImage: "slider.horizontal.3") { showFeatures = true }
                    .contentShape(Rectangle()).accessibilityIdentifier("graph.cluster.features")
                    .popover(isPresented: $showFeatures) { featureEditor }
                if let result = session.result {
                    Menu {
                        Button("All Clusters") { session.selectedCluster = nil }
                        ForEach(result.clusters) { cluster in
                            Button("Cluster \(cluster.id + 1) · \(cluster.members.count) nodes") { session.selectedCluster = cluster.id }
                        }
                    } label: {
                        Text(session.selectedCluster.map { "Cluster \($0 + 1)" } ?? "\(result.clusters.count) clusters")
                    }
                    .contentShape(Rectangle()).accessibilityIdentifier("graph.cluster.selection")
                    if session.selectedCluster != nil {
                        Button("Details…") { showMembers = true }
                            .contentShape(Rectangle()).accessibilityIdentifier("graph.cluster.details")
                            .popover(isPresented: $showMembers) { clusterDetails(result: result) }
                    }
                }
            }
            if state.isSpatial {
                Text("Layers show node roles · Context follows analyzed neighbors")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let result = session.result {
                Text("\(result.membership.count) analyzed · \(result.featureCount) features · PCA retains \(Int(result.retainedVariance * 100))% of variance")
                    .font(.caption2).foregroundStyle(.secondary)
                if !result.unassignedIDs.isEmpty || !result.unpositionedIDs.isEmpty {
                    Text("\(result.unassignedIDs.count) without informative features · \(result.unpositionedIDs.count) unpositioned in gutter")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }

    private var featureEditor: some View {
        @Bindable var session = state.clusterSession
        let metadata = Set(state.document.nodes.flatMap { $0.metadata.keys }).sorted()
        let metrics = Set(state.document.nodes.flatMap { $0.metrics.keys }).sorted()
        return ScrollView {
            Form {
                Text("Feature Analysis").font(.headline)
                Picker("Compare", selection: $session.configuration.role) {
                    ForEach(GraphNodeRole.allCases, id: \.self) { role in Text(role.displayName).tag(role) }
                }
                Stepper("Requested clusters: \(session.configuration.clusterCount)", value: $session.configuration.clusterCount, in: 2...24)
                weight("Types", value: $session.configuration.typeWeight)
                weight("Relationships", value: $session.configuration.relationshipWeight)
                weight("Attributes", value: $session.configuration.attributeWeight)
                Section("Categorical Attributes") {
                    if metadata.isEmpty { Text("No metadata attributes in this graph").foregroundStyle(.secondary) }
                    ForEach(metadata, id: \.self) { name in
                        Toggle(name, isOn: membership(name, set: $session.configuration.metadataKeys))
                    }
                }
                Section("Numeric Metrics") {
                    if metrics.isEmpty { Text("No numeric metrics in this graph").foregroundStyle(.secondary) }
                    ForEach(metrics, id: \.self) { name in
                        Toggle(name, isOn: membership(name, set: $session.configuration.metricKeys))
                    }
                }
                Text("Clusters use weighted features. PCA is a display approximation; overlapping points retain distinct identities.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Done") { showFeatures = false }.contentShape(Rectangle())
            }.formStyle(.grouped).padding(8)
        }.frame(width: 340, height: 460)
    }

    private func weight(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: 0...3, step: 0.5).accessibilityLabel(title + " weight")
            Text(value.wrappedValue, format: .number.precision(.fractionLength(1))).monospacedDigit().frame(width: 28)
        }
    }

    private func membership(_ name: String, set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(name) }, set: { value in
            if value { set.wrappedValue.insert(name) } else { set.wrappedValue.remove(name) }
        })
    }

    private func clusterDetails(result: GraphClusterResult) -> some View {
        let cluster = result.clusters.first { $0.id == state.clusterSession.selectedCluster }
        let labels = Dictionary(uniqueKeysWithValues: state.document.nodes.map { ($0.id, $0.label) })
        return VStack(alignment: .leading, spacing: 10) {
            if let cluster {
                Text("Cluster \(cluster.id + 1) · \(cluster.members.count) nodes").font(.headline)
                Text("Strongest Mean Features").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(cluster.features.enumerated()), id: \.offset) { _, feature in
                    Text(feature).font(.caption).lineLimit(2).help(feature).textSelection(.enabled)
                }
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(cluster.members, id: \.self) { id in
                            Button {
                                state.selectNode(id); showMembers = false
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(labels[id] ?? id)
                                    Text(id).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("graph.cluster.member." + id)
                            Divider()
                        }
                    }
                }
            }
        }.padding(16).frame(width: 360, height: 380)
    }
}
