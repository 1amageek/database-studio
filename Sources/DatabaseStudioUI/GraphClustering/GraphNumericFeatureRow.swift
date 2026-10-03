import SwiftUI

struct GraphNumericFeatureRow: View {
    @Binding var feature: GraphNumericFeature
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(feature.title).font(.callout.weight(.medium)).lineLimit(2)
                Spacer()
                Button("Remove", systemImage: "minus.circle", action: remove)
                    .labelStyle(.iconOnly).buttonStyle(.borderless).contentShape(Rectangle())
            }
            HStack {
                Picker("Transform", selection: $feature.transform) {
                    ForEach(GraphNumericFeature.Transform.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 110).contentShape(Rectangle())
                    .accessibilityLabel("Transform " + feature.title)
                Text("Weight").font(.caption).foregroundStyle(.secondary)
                Slider(value: $feature.weight, in: 0...8, step: 0.25)
                    .accessibilityLabel("Weight " + feature.title).contentShape(Rectangle())
                Text(feature.weight, format: .number.precision(.fractionLength(2))).font(.caption.monospacedDigit()).frame(width: 35)
            }
        }.padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}
