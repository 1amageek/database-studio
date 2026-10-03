import SwiftUI

struct GraphAnalysisSettings: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GraphClusterConfiguration
    @State private var numerator: String
    @State private var denominator: String
    private let metrics: [String]
    private let categories: [String]
    private let counts: [String: Int]
    private let nodeCount: Int
    private let hasQualityFlags: Bool
    private let apply: (GraphClusterConfiguration) -> Void

    init(document: GraphDocument, configuration: GraphClusterConfiguration, apply: @escaping (GraphClusterConfiguration) -> Void) {
        _draft = State(initialValue: configuration)
        metrics = Set(document.nodes.flatMap { $0.metrics.keys }).sorted()
        categories = Set(document.nodes.flatMap { $0.metadata.keys }).sorted()
        counts = Dictionary(uniqueKeysWithValues: metrics.map { key in (key, document.nodes.filter { $0.metrics[key] != nil }.count) })
        nodeCount = document.nodes.count
        hasQualityFlags = document.nodes.contains { $0.metadata["Quality flags"] != nil }
        _numerator = State(initialValue: metrics.first ?? "")
        _denominator = State(initialValue: metrics.dropFirst().first ?? metrics.first ?? "")
        self.apply = apply
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Analysis Setup").font(.title2.weight(.semibold))
                    Text("Choose what makes rows comparable, then choose how to view the result.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(nodeCount) rows").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(20)
            Picker("Analysis", selection: $draft.mode) {
                ForEach(GraphClusterConfiguration.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 16).contentShape(Rectangle())
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(draft.mode == .numeric ? "MEASUREMENTS" : "ATTRIBUTES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if metrics.isEmpty { Text("This source has no numeric columns.").foregroundStyle(.secondary) }
                        ForEach(metrics, id: \.self) { key in
                            HStack {
                                Toggle(isOn: metricSelection(key)) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(key).font(.callout).lineLimit(2)
                                        Text("\(counts[key, default: 0]) / \(nodeCount) available").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }.contentShape(Rectangle()).accessibilityIdentifier("analysis.metric." + key)
                                    .disabled(draft.mode == .numeric && draft.numericFeatures.count >= 32 && !draft.numericFeatures.contains { $0.numerator == key && $0.denominator == nil })
                            }
                            Divider()
                        }
                        if draft.mode == .graph {
                            Text("CATEGORIES").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
                            ForEach(categories, id: \.self) { key in
                                Toggle(key, isOn: Binding(get: { draft.metadataKeys.contains(key) }, set: { if $0 { draft.metadataKeys.insert(key) } else { draft.metadataKeys.remove(key) } }))
                                    .contentShape(Rectangle())
                            }
                        }
                    }.padding(18)
                }.frame(width: 270)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if draft.mode == .numeric { numericSettings } else { graphSettings }
                        Divider()
                        HStack {
                            Text("Clusters").font(.callout.weight(.medium))
                            Spacer()
                            Stepper("\(draft.clusterCount)", value: $draft.clusterCount, in: 2...24).fixedSize().contentShape(Rectangle())
                                .accessibilityIdentifier("analysis.clusterCount")
                        }
                        Text("The requested count defines a partition, not evidence that natural groups exist. Inspect group profiles and compare nearby counts.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(18)
                }.frame(maxWidth: .infinity)
            }
            Divider()
            HStack {
                Text(draft.mode == .numeric ? "\(draft.numericFeatures.count) features · \(draft.numericFeatures.reduce(0) { $0 + ($1.denominator == nil ? 0 : 1) }) ratios" : "Weighted graph features")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).contentShape(Rectangle())
                Button("Run Analysis") { apply(draft); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).contentShape(Rectangle())
                    .disabled(draft.mode == .numeric && (draft.numericFeatures.isEmpty || !draft.numericFeatures.contains { $0.weight > 0 }))
                    .accessibilityIdentifier("analysis.run")
            }.padding(16)
        }.frame(width: 800, height: 650)
    }

    private func metricSelection(_ key: String) -> Binding<Bool> {
        Binding(get: {
            draft.mode == .numeric ? draft.numericFeatures.contains { $0.numerator == key && $0.denominator == nil } : draft.metricKeys.contains(key)
        }, set: { enabled in
            if draft.mode == .graph {
                if enabled { draft.metricKeys.insert(key) } else { draft.metricKeys.remove(key) }
            } else if enabled {
                if draft.numericFeatures.count < 32 { draft.numericFeatures.append(.init(numerator: key)) }
            } else { draft.numericFeatures.removeAll { $0.numerator == key && $0.denominator == nil } }
        })
    }

    private var numericSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("1. Build the feature space").font(.headline)
            if draft.numericFeatures.isEmpty { Text("Select measurements on the left, or create a ratio below.").foregroundStyle(.secondary).font(.callout) }
            ForEach($draft.numericFeatures) { $feature in
                GraphNumericFeatureRow(feature: $feature) { draft.numericFeatures.removeAll { $0.id == feature.id } }
            }
            ratioEditor
            Text("Linear keeps signed values. Log10 requires positive values. Asinh keeps zero and negative values while compressing extremes. Each column is centered by its median and scaled by its IQR; zero IQR uses one transformed unit.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("2. Choose comparison conditions").font(.headline)
            categoryPicker("Subtract group median", selection: $draft.comparisonKey)
            if hasQualityFlags {
                Toggle("Exclude rows with source quality flags", isOn: $draft.excludesFlaggedRows).contentShape(Rectangle())
            }
            Text("Incomplete rows and invalid transforms are excluded with reasons. Missing and singleton comparison groups are excluded. The original rows stay available for inspection.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("3. Choose the display").font(.headline)
            Picker("2D positions", selection: $draft.projection) {
                ForEach(GraphClusterConfiguration.Projection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.contentShape(Rectangle()).accessibilityIdentifier("analysis.projection")
            if draft.projection == .axes {
                featurePicker("X", selection: $draft.xFeatureID)
                featurePicker("Y", selection: $draft.yFeatureID)
            } else { Text("PCA approximates distances. Membership is computed using every selected feature, before projection.").font(.caption).foregroundStyle(.secondary) }
            categoryPicker("3D layers", selection: $draft.layerKey)
            Text("Layers share XY coordinates and scale. Category height is a label, not a measurement.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var ratioEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create a ratio").font(.callout.weight(.medium))
            HStack {
                Picker("Numerator", selection: $numerator) { ForEach(metrics, id: \.self) { Text($0).tag($0) } }.labelsHidden().contentShape(Rectangle()).accessibilityLabel("Ratio numerator")
                Text("/").foregroundStyle(.secondary)
                Picker("Denominator", selection: $denominator) { ForEach(metrics, id: \.self) { Text($0).tag($0) } }.labelsHidden().contentShape(Rectangle()).accessibilityLabel("Ratio denominator")
                Button("Add") {
                    let feature = GraphNumericFeature(numerator: numerator, denominator: denominator)
                    if !draft.numericFeatures.contains(where: { $0.id == feature.id }) { draft.numericFeatures.append(feature) }
                }.contentShape(Rectangle()).disabled(metrics.isEmpty || numerator == denominator || draft.numericFeatures.count >= 32)
            }
            Text("The denominator must be positive. Raw values and derived ratios remain separate selections.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func categoryPicker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(String?.none)
            ForEach(categories, id: \.self) { Text($0).tag(Optional($0)) }
        }.contentShape(Rectangle())
    }

    private func featurePicker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("Automatic").tag(String?.none)
            ForEach(draft.numericFeatures) { Text($0.title).tag(Optional($0.id)) }
        }.contentShape(Rectangle()).accessibilityLabel(title + " feature")
    }

    private var graphSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Compare", selection: $draft.role) { ForEach(GraphNodeRole.allCases, id: \.self) { Text($0.displayName).tag($0) } }.contentShape(Rectangle())
            familyWeight("Types", value: $draft.typeWeight)
            familyWeight("Relationships", value: $draft.relationshipWeight)
            familyWeight("Attributes", value: $draft.attributeWeight)
            Text("Exact types, directed relationships and selected attributes define similarity. PCA is a display approximation.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func familyWeight(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title); Slider(value: value, in: 0...3, step: 0.5).contentShape(Rectangle()); Text(value.wrappedValue, format: .number.precision(.fractionLength(1))).monospacedDigit().frame(width: 30) }
    }
}
