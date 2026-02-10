import Foundation
import CoreGraphics

/// ベクトル空間上の単一ポイント
public struct VectorPoint: Identifiable, Sendable {
    public let id: String
    public var embedding: [Float]
    public var projected: CGPoint
    public var fields: [String: String]
    public var label: String

    public init(
        id: String,
        embedding: [Float],
        projected: CGPoint = .zero,
        fields: [String: String] = [:],
        label: String = ""
    ) {
        self.id = id
        self.embedding = embedding
        self.projected = projected
        self.fields = fields
        self.label = label.isEmpty ? id : label
    }
}

/// ベクトルドキュメント
public struct VectorDocument: Sendable {
    public var points: [VectorPoint]
    public var entityName: String
    public var embeddingField: String
    public var dimensions: Int
    public var fieldNames: [String]

    public init(
        points: [VectorPoint] = [],
        entityName: String = "",
        embeddingField: String = "embedding",
        dimensions: Int = 0,
        fieldNames: [String] = []
    ) {
        self.points = points
        self.entityName = entityName
        self.embeddingField = embeddingField
        self.dimensions = dimensions
        self.fieldNames = fieldNames
    }

    /// CatalogDataAccess の結果から構築
    public init(
        items: [[String: Any]],
        entityName: String,
        embeddingField: String,
        labelField: String? = nil
    ) {
        self.entityName = entityName
        self.embeddingField = embeddingField

        var allFields: Set<String> = []
        var points: [VectorPoint] = []
        var dims = 0

        for item in items {
            guard let embedding = Self.extractEmbedding(item[embeddingField]) else { continue }

            if dims == 0 { dims = embedding.count }

            let id: String
            if let sid = item["id"] as? String { id = sid }
            else if let sid = item["_id"] as? String { id = sid }
            else { id = UUID().uuidString }

            let label: String
            if let lf = labelField, let v = item[lf] { label = String(describing: v) }
            else { label = id }

            var fields: [String: String] = [:]
            for (key, value) in item where key != embeddingField {
                fields[key] = String(describing: value)
                allFields.insert(key)
            }

            points.append(VectorPoint(
                id: id,
                embedding: embedding,
                fields: fields,
                label: label
            ))
        }

        self.points = points
        self.dimensions = dims
        self.fieldNames = allFields.sorted()
    }

    private static func extractEmbedding(_ value: Any?) -> [Float]? {
        guard let value else { return nil }
        if let arr = value as? [Float] { return arr }
        if let arr = value as? [Double] { return arr.map { Float($0) } }
        if let arr = value as? [Int] { return arr.map { Float($0) } }
        if let arr = value as? [Any] {
            let floats = arr.compactMap { elem -> Float? in
                if let d = elem as? Double { return Float(d) }
                if let f = elem as? Float { return f }
                if let i = elem as? Int { return Float(i) }
                return nil
            }
            return floats.count == arr.count ? floats : nil
        }
        return nil
    }
}
