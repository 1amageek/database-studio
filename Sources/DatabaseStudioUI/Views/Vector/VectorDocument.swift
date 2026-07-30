import Foundation
import CoreGraphics

/// A record represented as a point in vector space.
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

/// A validated vector snapshot presented by Vector Explorer.
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

    /// Creates a vector snapshot from database records.
    public init(
        records: [StudioRecord],
        entityName: String,
        embeddingField: String,
        labelField: String? = nil
    ) throws {
        self.entityName = entityName
        self.embeddingField = embeddingField

        var allFields: Set<String> = []
        var points: [VectorPoint] = []
        points.reserveCapacity(records.count)
        var dimensionCount: Int?

        for record in records {
            let identifier = record.id
            let recordFields = record.fields

            guard let embeddingValue = recordFields[embeddingField] else {
                throw VectorDocumentError.missingEmbedding(identifier: identifier, field: embeddingField)
            }
            guard let embedding = Self.embedding(from: embeddingValue), !embedding.isEmpty else {
                throw VectorDocumentError.invalidEmbedding(identifier: identifier, field: embeddingField)
            }
            guard embedding.allSatisfy(\.isFinite) else {
                throw VectorDocumentError.nonFiniteEmbedding(identifier: identifier, field: embeddingField)
            }

            if let expectedDimensionCount = dimensionCount {
                guard embedding.count == expectedDimensionCount else {
                    throw VectorDocumentError.inconsistentDimensions(
                        identifier: identifier,
                        expected: expectedDimensionCount,
                        actual: embedding.count
                    )
                }
            } else {
                dimensionCount = embedding.count
            }

            let label: String
            if let labelField, let labelValue = recordFields[labelField] {
                label = String(describing: labelValue)
            } else {
                label = identifier
            }

            var fields: [String: String] = [:]
            for (key, value) in recordFields where key != embeddingField {
                fields[key] = String(describing: value)
                allFields.insert(key)
            }

            points.append(VectorPoint(
                id: identifier,
                embedding: embedding,
                fields: fields,
                label: label
            ))
        }

        self.points = points
        self.dimensions = dimensionCount ?? 0
        self.fieldNames = allFields.sorted()
    }

    private static func embedding(from value: Any) -> [Float]? {
        if let values = value as? [Float] { return values }
        if let values = value as? [Double] { return values.map { Float($0) } }
        if let values = value as? [Int] { return values.map { Float($0) } }
        if let values = value as? [Any] {
            var embedding: [Float] = []
            embedding.reserveCapacity(values.count)
            for element in values {
                if let doubleValue = element as? Double {
                    embedding.append(Float(doubleValue))
                } else if let floatValue = element as? Float {
                    embedding.append(floatValue)
                } else if let integerValue = element as? Int {
                    embedding.append(Float(integerValue))
                } else {
                    return nil
                }
            }
            return embedding
        }
        return nil
    }
}

/// A deterministic vector snapshot validation failure.
public enum VectorDocumentError: LocalizedError, Sendable {
    case missingEmbedding(identifier: String, field: String)
    case invalidEmbedding(identifier: String, field: String)
    case nonFiniteEmbedding(identifier: String, field: String)
    case inconsistentDimensions(identifier: String, expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .missingEmbedding(let identifier, let field):
            return "Record \(identifier) has no \(field) embedding"
        case .invalidEmbedding(let identifier, let field):
            return "Record \(identifier) has an invalid \(field) embedding"
        case .nonFiniteEmbedding(let identifier, let field):
            return "Record \(identifier) has a non-finite value in its \(field) embedding"
        case .inconsistentDimensions(let identifier, let expected, let actual):
            return "Record \(identifier) has \(actual) embedding dimensions; expected \(expected)"
        }
    }
}
