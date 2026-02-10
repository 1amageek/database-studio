import SwiftUI

/// ファセットフィルターのサイドバー
struct FacetSidebarView: View {
    @Bindable var state: SearchViewState

    var body: some View {
        List {
            modeSection
            statsSection
            if !state.facets.isEmpty {
                facetSections
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - モード

    private var modeSection: some View {
        Section("Match Mode") {
            Picker("Mode", selection: $state.matchMode) {
                ForEach(SearchMatchMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - 統計

    private var statsSection: some View {
        Section("Statistics") {
            LabeledContent("Documents", value: "\(state.document.items.count)")
                .font(.caption)
            if state.searchDuration > 0 {
                LabeledContent("Search Time", value: String(format: "%.1f ms", state.searchDuration * 1000))
                    .font(.caption)
            }
            LabeledContent("Results", value: "\(state.results.count)")
                .font(.caption)
        }
    }

    // MARK: - ファセット

    @ViewBuilder
    private var facetSections: some View {
        ForEach(state.facets) { facet in
            Section(facet.fieldName) {
                ForEach(facet.values) { fv in
                    facetValueButton(facet: facet, fv: fv)
                }
            }
        }
    }

    private func facetValueButton(facet: Facet, fv: FacetValue) -> some View {
        Button {
            state.toggleFacetValue(fieldName: facet.fieldName, value: fv.value)
        } label: {
            HStack {
                Image(systemName: fv.isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(fv.isSelected ? Color.accentColor : Color.secondary)
                    .font(.caption)

                Text(fv.value)
                    .font(.callout)
                    .lineLimit(1)

                Spacer()

                Text("\(fv.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
