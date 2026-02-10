import Foundation
import CoreLocation

/// 地図上に表示する単一ポイント
public struct MapPoint: Identifiable, Hashable, Sendable {
    public let id: String
    public var coordinate: CLLocationCoordinate2D
    public var label: String
    public var fields: [String: String]

    public init(
        id: String,
        coordinate: CLLocationCoordinate2D,
        label: String,
        fields: [String: String] = [:]
    ) {
        self.id = id
        self.coordinate = coordinate
        self.label = label
        self.fields = fields
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: MapPoint, rhs: MapPoint) -> Bool {
        lhs.id == rhs.id
    }
}

/// 地図ドキュメント
public struct MapDocument: Sendable {
    public var points: [MapPoint]
    public var entityName: String
    public var latitudeField: String
    public var longitudeField: String

    public init(
        points: [MapPoint] = [],
        entityName: String = "",
        latitudeField: String = "latitude",
        longitudeField: String = "longitude"
    ) {
        self.points = points
        self.entityName = entityName
        self.latitudeField = latitudeField
        self.longitudeField = longitudeField
    }
}

/// CatalogDataAccess の結果から MapDocument を構築
extension MapDocument {
    public init(
        items: [[String: Any]],
        entityName: String,
        latitudeField: String,
        longitudeField: String,
        labelField: String? = nil
    ) {
        self.entityName = entityName
        self.latitudeField = latitudeField
        self.longitudeField = longitudeField

        var points: [MapPoint] = []
        for item in items {
            guard let lat = Self.extractDouble(item[latitudeField]),
                  let lng = Self.extractDouble(item[longitudeField]) else {
                continue
            }

            let id = Self.extractID(from: item)
            let label: String
            if let lf = labelField, let v = item[lf] {
                label = String(describing: v)
            } else {
                label = id
            }

            var fields: [String: String] = [:]
            for (key, value) in item {
                fields[key] = String(describing: value)
            }

            points.append(MapPoint(
                id: id,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                label: label,
                fields: fields
            ))
        }
        self.points = points
    }

    private static func extractDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let d = value as? Double { return d }
        if let f = value as? Float { return Double(f) }
        if let i = value as? Int { return Double(i) }
        if let i = value as? Int64 { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func extractID(from item: [String: Any]) -> String {
        if let id = item["id"] as? String { return id }
        if let id = item["_id"] as? String { return id }
        return UUID().uuidString
    }
}
