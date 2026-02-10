import Foundation
import CoreLocation

/// Map Preview 用サンプルデータ（東京周辺）
enum MapPreviewData {

    static let document: MapDocument = MapDocument(
        points: points,
        entityName: "Store",
        latitudeField: "latitude",
        longitudeField: "longitude"
    )

    static let points: [MapPoint] = [
        MapPoint(
            id: "store-001",
            coordinate: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
            label: "Tokyo Station",
            fields: ["type": "flagship", "revenue": "1200000"]
        ),
        MapPoint(
            id: "store-002",
            coordinate: CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7004),
            label: "Shibuya Center",
            fields: ["type": "standard", "revenue": "850000"]
        ),
        MapPoint(
            id: "store-003",
            coordinate: CLLocationCoordinate2D(latitude: 35.6938, longitude: 139.7034),
            label: "Shinjuku West",
            fields: ["type": "flagship", "revenue": "980000"]
        ),
        MapPoint(
            id: "store-004",
            coordinate: CLLocationCoordinate2D(latitude: 35.7101, longitude: 139.8107),
            label: "Asakusa Branch",
            fields: ["type": "standard", "revenue": "620000"]
        ),
        MapPoint(
            id: "store-005",
            coordinate: CLLocationCoordinate2D(latitude: 35.6585, longitude: 139.7454),
            label: "Roppongi Hills",
            fields: ["type": "premium", "revenue": "1500000"]
        ),
        MapPoint(
            id: "store-006",
            coordinate: CLLocationCoordinate2D(latitude: 35.6292, longitude: 139.7747),
            label: "Shinagawa Gate",
            fields: ["type": "standard", "revenue": "720000"]
        ),
        MapPoint(
            id: "store-007",
            coordinate: CLLocationCoordinate2D(latitude: 35.7296, longitude: 139.7109),
            label: "Ikebukuro East",
            fields: ["type": "standard", "revenue": "810000"]
        ),
        MapPoint(
            id: "store-008",
            coordinate: CLLocationCoordinate2D(latitude: 35.6684, longitude: 139.6833),
            label: "Shimokitazawa",
            fields: ["type": "compact", "revenue": "450000"]
        ),
        MapPoint(
            id: "store-009",
            coordinate: CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967),
            label: "Ueno Park",
            fields: ["type": "standard", "revenue": "670000"]
        ),
        MapPoint(
            id: "store-010",
            coordinate: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            label: "Kichijoji",
            fields: ["type": "compact", "revenue": "520000"]
        ),
        MapPoint(
            id: "store-011",
            coordinate: CLLocationCoordinate2D(latitude: 35.6434, longitude: 139.6679),
            label: "Jiyugaoka",
            fields: ["type": "premium", "revenue": "890000"]
        ),
        MapPoint(
            id: "store-012",
            coordinate: CLLocationCoordinate2D(latitude: 35.6818, longitude: 139.7657),
            label: "Marunouchi",
            fields: ["type": "flagship", "revenue": "1350000"]
        ),
    ]
}
