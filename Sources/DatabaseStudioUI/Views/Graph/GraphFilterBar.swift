import SwiftUI

/// キャンバス上部のフィルターバー（チップ一覧 + 追加メニュー）
struct GraphFilterBar: View {
    @Bindable var state: GraphViewState

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.filterTokens) { token in
                        GraphFilterChip(
                            token: token,
                            state: state
                        )
                    }
                }
            }

            if state.filterTokens.count > 1 {
                Button {
                    state.clearAllFilterTokens()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear All Filters")
            }

            addFilterMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Add Filter Menu

    @ViewBuilder
    private var addFilterMenu: some View {
        Menu {
            Section("Quick Filters") {
                ForEach(GraphFilterPreset.allCases, id: \.label) { preset in
                    Button {
                        state.addPreset(preset)
                    } label: {
                        Label(preset.label, systemImage: preset.systemImage)
                    }
                }
            }

            Divider()

            Section("Add Filter") {
                ForEach(GraphFilterFacetCategory.allCases, id: \.label) { category in
                    Button {
                        state.addFilterToken(for: category)
                    } label: {
                        Label(category.label, systemImage: category.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// 個別フィルターチップ
struct GraphFilterChip: View {
    let token: GraphFilterToken
    @Bindable var state: GraphViewState
    @State private var showEditor = false

    var body: some View {
        Button {
            showEditor.toggle()
        } label: {
            HStack(spacing: 4) {
                if token.mode == .exclude {
                    Image(systemName: "minus.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                Text(token.facet.categoryLabel)
                    .font(.caption.weight(.medium))

                Text(token.facet.valueSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    state.removeFilterToken(token)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(chipBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showEditor) {
            GraphFilterEditorPopover(
                token: token,
                state: state,
                onUpdate: { updated in
                    state.updateFilterToken(updated)
                },
                onDelete: {
                    state.removeFilterToken(token)
                    showEditor = false
                }
            )
        }
    }

    private var chipBackground: some ShapeStyle {
        token.mode == .exclude
            ? AnyShapeStyle(Color.red.opacity(0.12))
            : AnyShapeStyle(Color.accentColor.opacity(0.12))
    }
}
