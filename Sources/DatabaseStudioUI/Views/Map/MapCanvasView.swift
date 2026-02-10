import SwiftUI
import MapKit

/// MapKit Map を使った地図描画ビュー
struct MapCanvasView: View {
    @Bindable var state: MapViewState

    var body: some View {
        Map(position: $state.cameraPosition) {
            // 全ポイントのマーカー
            ForEach(state.document.points) { point in
                let isSelected = state.selectedPointID == point.id
                let isSearchResult = state.searchResultIDs.contains(point.id)
                let isCenter = state.searchCenter?.id == point.id

                Annotation(
                    isSelected || isCenter ? point.label : "",
                    coordinate: point.coordinate,
                    anchor: .bottom
                ) {
                    VStack(spacing: 0) {
                        Image(systemName: isCenter ? "star.fill" : "mappin.circle.fill")
                            .font(isSelected || isCenter ? .title2 : .body)
                            .foregroundStyle(pinColor(
                                isSelected: isSelected,
                                isCenter: isCenter,
                                isSearchResult: isSearchResult
                            ))
                            .background {
                                if isSelected || isCenter {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 28, height: 28)
                                }
                            }
                    }
                    .onTapGesture {
                        handleTap(point: point)
                    }
                }
            }

            // Radius モードの円
            if state.searchMode == .radius,
               let center = state.searchCenter ?? state.selectedPoint {
                MapCircle(
                    center: center.coordinate,
                    radius: CLLocationDistance(state.searchRadius)
                )
                .foregroundStyle(.blue.opacity(0.08))
                .stroke(.blue.opacity(0.4), lineWidth: 1.5)
            }

            // KNN モードの接続線
            if state.searchMode == .knn,
               let center = state.searchCenter ?? state.selectedPoint {
                ForEach(state.searchResults) { result in
                    MapPolyline(coordinates: [
                        center.coordinate,
                        result.point.coordinate
                    ])
                    .stroke(.blue.opacity(0.3), lineWidth: 1)
                }
            }
        }
        .mapStyle(state.mapStyle.mapStyle)
        .mapControls {
            MapCompass()
            MapScaleView()
            MapZoomStepper()
        }
    }

    // MARK: - ピンカラー

    private func pinColor(isSelected: Bool, isCenter: Bool, isSearchResult: Bool) -> Color {
        if isCenter { return .orange }
        if isSelected { return .red }
        if isSearchResult { return .green }

        switch state.searchMode {
        case .pins:
            return .blue
        case .knn, .radius:
            return state.searchResults.isEmpty ? .blue : .secondary.opacity(0.5)
        }
    }

    // MARK: - タップ処理

    private func handleTap(point: MapPoint) {
        switch state.searchMode {
        case .pins:
            state.selectedPointID = point.id

        case .knn, .radius:
            if state.searchCenter == nil {
                state.searchCenter = point
                state.selectedPointID = point.id
            } else if state.searchCenter?.id == point.id {
                state.searchCenter = nil
            } else {
                state.selectedPointID = point.id
            }
        }
    }
}
