import SwiftUI

struct GraphClusterControls: View {
    @Bindable var state: GraphViewState
    @State private var showFeatures = false
    @State private var showMembers = false
    @State private var showExcluded = false
    @State private var openedInitialSettings = false

    var body: some View {
        @Bindable var session = state.clusterSession
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button("Configure…", systemImage: "slider.horizontal.3") { showFeatures = true }
                    .contentShape(Rectangle()).accessibilityIdentifier("graph.cluster.features")
                    .sheet(isPresented: $showFeatures) {
                        GraphAnalysisSettings(document: state.document, configuration: session.configuration) { session.configuration = $0; session.invalidate() }
                    }
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
                Text(session.configuration.layerKey.map { "Layers: " + $0 + " · Shared XY coordinates" } ?? "Layers show node roles · Shared XY coordinates")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if session.isLoading {
                HStack { ProgressView().controlSize(.small); Button("Cancel Analysis") { session.cancel() }.contentShape(Rectangle()) }
            } else if session.result == nil && !session.configuration.numericFeatures.isEmpty {
                Button("Run Analysis") { session.invalidate() }.contentShape(Rectangle())
            }
            if let result = session.result {
                Text("\(result.membership.count) analyzed · \(result.featureCount) features" + (result.axes.isEmpty ? " · PCA retains \(Int(result.retainedVariance * 100))% of variance" : " · Selected axes"))
                    .font(.caption2).foregroundStyle(.secondary)
                if !result.unassignedIDs.isEmpty || !result.unpositionedIDs.isEmpty {
                    Button("\(result.unassignedIDs.count) excluded · \(result.unpositionedIDs.count) unpositioned") { showExcluded = true }
                        .buttonStyle(.plain).contentShape(Rectangle())
                        .popover(isPresented: $showExcluded) { excludedRows(result) }
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
        .onAppear {
            if !openedInitialSettings && session.configuration.mode == .numeric && session.configuration.numericFeatures.isEmpty {
                openedInitialSettings = true; showFeatures = true
            }
        }
    }

    private func excludedRows(_ result: GraphClusterResult) -> some View {
        let labels = Dictionary(uniqueKeysWithValues: state.document.nodes.map { ($0.id, $0.label) })
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Excluded Rows").font(.headline)
                ForEach(result.unassignedIDs.sorted(), id: \.self) { id in
                    Button { state.selectNode(id); showExcluded = false } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(labels[id] ?? id)
                            Text(result.exclusionReasons[id] ?? "No informative features").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider()
                }
            }.padding(16)
        }.frame(width: 420, height: 350)
    }

    private func clusterDetails(result: GraphClusterResult) -> some View {
        let cluster = result.clusters.first { $0.id == state.clusterSession.selectedCluster }
        let labels = Dictionary(uniqueKeysWithValues: state.document.nodes.map { ($0.id, $0.label) })
        return VStack(alignment: .leading, spacing: 10) {
            if let cluster {
                Text("Cluster \(cluster.id + 1) · \(cluster.members.count) nodes").font(.headline)
                if let profiles = result.profiles[cluster.id] {
                    Text("Original-value profile · Median [Q1, Q3]").font(.caption).foregroundStyle(.secondary)
                    ForEach(profiles) { profile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.title).font(.caption.weight(.medium))
                            Text("\(profile.median.formatted(.number.precision(.significantDigits(4)))) [\(profile.lowerQuartile.formatted(.number.precision(.significantDigits(4)))), \(profile.upperQuartile.formatted(.number.precision(.significantDigits(4))))] · population \(profile.populationMedian.formatted(.number.precision(.significantDigits(4))))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else {
                Text("Strongest Mean Features").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(cluster.features.enumerated()), id: \.offset) { _, feature in
                    Text(feature).font(.caption).lineLimit(2).help(feature).textSelection(.enabled)
                }
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
        }.padding(16).frame(width: 460, height: 500)
    }
}
