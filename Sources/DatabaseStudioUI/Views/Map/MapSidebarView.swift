import SwiftUI

/// 地図サイドバー: モード切替、パラメータ、ポイント一覧
struct MapSidebarView: View {
    @Bindable var state: MapViewState

    var body: some View {
        List {
            modeSection
            parametersSection
            pointsSection
        }
        .listStyle(.sidebar)
    }

    // MARK: - モード切替

    private var modeSection: some View {
        Section("Mode") {
            ForEach(MapSearchMode.allCases) { mode in
                modeButton(mode)
            }
        }
    }

    private func modeButton(_ mode: MapSearchMode) -> some View {
        let isActive = state.searchMode == mode
        return Button {
            state.searchMode = mode
            state.searchCenter = nil
        } label: {
            Label(mode.rawValue, systemImage: mode.systemImage)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .fontWeight(isActive ? .semibold : .regular)
    }

    // MARK: - パラメータ

    @ViewBuilder
    private var parametersSection: some View {
        switch state.searchMode {
        case .pins:
            EmptyView()

        case .knn:
            Section("KNN Parameters") {
                Stepper("K: \(state.kValue)", value: $state.kValue, in: 1...50)

                if state.searchCenter != nil {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(state.searchCenter?.label ?? "")
                            .font(.caption)
                        Spacer()
                        Button("Clear") {
                            state.searchCenter = nil
                        }
                        .font(.caption)
                    }
                } else {
                    Text("Tap a point on the map to set the center")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .radius:
            Section("Radius Parameters") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Radius: \(formattedRadius)")
                        .font(.caption.monospacedDigit())
                    Slider(
                        value: $state.searchRadius,
                        in: 100...50_000,
                        step: 100
                    )
                }

                if state.searchCenter != nil {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(state.searchCenter?.label ?? "")
                            .font(.caption)
                        Spacer()
                        Button("Clear") {
                            state.searchCenter = nil
                        }
                        .font(.caption)
                    }
                } else {
                    Text("Tap a point on the map to set the center")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        // 検索結果
        if !state.searchResults.isEmpty {
            Section("Results (\(state.searchResults.count))") {
                ForEach(state.searchResults) { result in
                    Button {
                        state.selectedPointID = result.id
                    } label: {
                        HStack {
                            Text(result.point.label)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            Text(result.formattedDistance)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - ポイント一覧

    private var pointsSection: some View {
        Section("Points (\(state.document.points.count))") {
            ForEach(state.document.points) { point in
                Button {
                    state.focusOnPoint(point)
                } label: {
                    HStack {
                        Image(systemName: "mappin")
                            .foregroundStyle(
                                state.selectedPointID == point.id ? .red : .blue
                            )
                            .font(.caption)

                        Text(point.label)
                            .font(.callout)
                            .lineLimit(1)

                        Spacer()

                        Text(coordinateText(point))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - ヘルパー

    private var formattedRadius: String {
        if state.searchRadius < 1000 {
            return String(format: "%.0f m", state.searchRadius)
        } else {
            return String(format: "%.1f km", state.searchRadius / 1000)
        }
    }

    private func coordinateText(_ point: MapPoint) -> String {
        String(format: "%.3f, %.3f", point.coordinate.latitude, point.coordinate.longitude)
    }
}
