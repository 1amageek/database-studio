import SwiftUI
import CoreLocation

/// 選択ポイントの詳細インスペクター
struct MapInspectorView: View {
    let point: MapPoint
    let searchResults: [MapSearchResult]
    let searchMode: MapSearchMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                coordinateSection
                fieldsSection
                if !searchResults.isEmpty {
                    searchResultsSection
                }
            }
            .padding()
        }
    }

    // MARK: - 座標

    private var coordinateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(point.label, systemImage: "mappin.circle.fill")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Latitude")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.6f", point.coordinate.latitude))
                        .font(.caption.monospacedDigit())
                }
                GridRow {
                    Text("Longitude")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.6f", point.coordinate.longitude))
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    // MARK: - フィールド

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fields")
                .font(.subheadline.weight(.semibold))

            if point.fields.isEmpty {
                Text("No fields")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(point.fields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        GridRow {
                            Text(key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 80, alignment: .trailing)
                            Text(value)
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 検索結果

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(searchMode.rawValue) Results")
                .font(.subheadline.weight(.semibold))

            ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, result in
                HStack {
                    Text("\(index + 1).")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(result.point.label)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(result.formattedDistance)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
