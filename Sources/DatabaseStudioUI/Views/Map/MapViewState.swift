import SwiftUI
import MapKit
import CoreLocation

/// 地図可視化の検索モード
enum MapSearchMode: String, CaseIterable, Identifiable {
    case pins = "Pins"
    case knn = "KNN"
    case radius = "Radius"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .pins: return "mappin.and.ellipse"
        case .knn: return "target"
        case .radius: return "circle.dashed"
        }
    }
}

/// KNN / Radius 検索結果
struct MapSearchResult: Identifiable {
    let id: String
    let point: MapPoint
    let distance: Double

    var formattedDistance: String {
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
}

/// 地図可視化の状態管理
@Observable @MainActor
final class MapViewState {

    // MARK: - データ

    var document: MapDocument {
        didSet { invalidateCache() }
    }

    // MARK: - 検索モード

    var searchMode: MapSearchMode = .pins {
        didSet { computeSearchResults() }
    }

    // MARK: - 選択

    var selectedPointID: String? {
        didSet { computeSearchResults() }
    }

    var selectedPoint: MapPoint? {
        guard let id = selectedPointID else { return nil }
        return pointMap[id]
    }

    // MARK: - KNN パラメータ

    var kValue: Int = 5 {
        didSet { computeSearchResults() }
    }

    // MARK: - Radius パラメータ

    /// 検索半径（メートル）
    var searchRadius: Double = 1000 {
        didSet { computeSearchResults() }
    }

    // MARK: - 検索結果

    private(set) var searchResults: [MapSearchResult] = [] {
        didSet { cachedSearchResultIDs = Set(searchResults.map(\.id)) }
    }

    /// KNN/Radius 検索の中心点（タップで設定）
    var searchCenter: MapPoint? {
        didSet { computeSearchResults() }
    }

    /// 検索結果に含まれるポイント ID（キャッシュ済み）
    private(set) var cachedSearchResultIDs: Set<String> = []

    var searchResultIDs: Set<String> { cachedSearchResultIDs }

    // MARK: - カメラ

    var cameraPosition: MapCameraPosition = .automatic

    // MARK: - マップスタイル

    var mapStyle: MapStyleOption = .standard

    // MARK: - キャッシュ

    private var pointMap: [String: MapPoint] = [:]

    // MARK: - 初期化

    init(document: MapDocument) {
        self.document = document
        self.pointMap = Dictionary(uniqueKeysWithValues: document.points.map { ($0.id, $0) })
    }

    // MARK: - ドキュメント更新

    func updateDocument(_ newDocument: MapDocument) {
        document = newDocument
    }

    // MARK: - キャッシュ管理

    private func invalidateCache() {
        pointMap = Dictionary(uniqueKeysWithValues: document.points.map { ($0.id, $0) })
        searchResults = []
    }

    // MARK: - 検索計算

    func computeSearchResults() {
        guard let center = searchCenter ?? selectedPoint else {
            searchResults = []
            return
        }

        let centerLocation = CLLocation(
            latitude: center.coordinate.latitude,
            longitude: center.coordinate.longitude
        )

        switch searchMode {
        case .pins:
            searchResults = []

        case .knn:
            let sorted = document.points
                .filter { $0.id != center.id }
                .map { point -> MapSearchResult in
                    let loc = CLLocation(
                        latitude: point.coordinate.latitude,
                        longitude: point.coordinate.longitude
                    )
                    return MapSearchResult(
                        id: point.id,
                        point: point,
                        distance: centerLocation.distance(from: loc)
                    )
                }
                .sorted { $0.distance < $1.distance }

            searchResults = Array(sorted.prefix(kValue))

        case .radius:
            searchResults = document.points
                .filter { $0.id != center.id }
                .compactMap { point -> MapSearchResult? in
                    let loc = CLLocation(
                        latitude: point.coordinate.latitude,
                        longitude: point.coordinate.longitude
                    )
                    let dist = centerLocation.distance(from: loc)
                    guard dist <= searchRadius else { return nil }
                    return MapSearchResult(
                        id: point.id,
                        point: point,
                        distance: dist
                    )
                }
                .sorted { $0.distance < $1.distance }
        }
    }

    // MARK: - カメラ操作

    func zoomToFit() {
        guard !document.points.isEmpty else { return }
        let coords = document.points.map(\.coordinate)
        let region = Self.regionToFit(coordinates: coords, padding: 1.3)
        cameraPosition = .region(region)
    }

    func focusOnPoint(_ point: MapPoint) {
        selectedPointID = point.id
        cameraPosition = .region(MKCoordinateRegion(
            center: point.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        ))
    }

    // MARK: - ヘルパー

    static func regionToFit(coordinates: [CLLocationCoordinate2D], padding: Double = 1.2) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.77),
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }

        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)

        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLng = lngs.min()!
        let maxLng = lngs.max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * padding, 0.01),
            longitudeDelta: max((maxLng - minLng) * padding, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// マップスタイルの選択肢
enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"

    var id: String { rawValue }

    var mapStyle: MapStyle {
        switch self {
        case .standard: return .standard
        case .satellite: return .imagery
        case .hybrid: return .hybrid
        }
    }
}
