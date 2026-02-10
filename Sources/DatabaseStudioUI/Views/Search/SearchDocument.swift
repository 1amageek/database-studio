import Foundation

/// 検索対象アイテム
public struct SearchableItem: Identifiable, Sendable {
    public let id: String
    public var textFields: [String: String]
    public var allFields: [String: String]

    public init(
        id: String,
        textFields: [String: String],
        allFields: [String: String] = [:]
    ) {
        self.id = id
        self.textFields = textFields
        self.allFields = allFields.isEmpty ? textFields : allFields
    }
}

/// 検索結果
public struct SearchResult: Identifiable, Sendable {
    public let id: String
    public let item: SearchableItem
    public let score: Double
    public let fieldScores: [String: Double]
    public let matchRanges: [String: [Range<String.Index>]]

    public init(
        item: SearchableItem,
        score: Double,
        fieldScores: [String: Double] = [:],
        matchRanges: [String: [Range<String.Index>]] = [:]
    ) {
        self.id = item.id
        self.item = item
        self.score = score
        self.fieldScores = fieldScores
        self.matchRanges = matchRanges
    }
}

/// 検索モード
public enum SearchMatchMode: String, CaseIterable, Identifiable, Sendable {
    case all = "All Terms"
    case any = "Any Term"
    case phrase = "Exact Phrase"

    public var id: String { rawValue }
}

/// ファセット
public struct Facet: Identifiable, Sendable {
    public let id: String
    public let fieldName: String
    public var values: [FacetValue]

    public init(fieldName: String, values: [FacetValue]) {
        self.id = fieldName
        self.fieldName = fieldName
        self.values = values
    }
}

/// ファセット値
public struct FacetValue: Identifiable, Sendable {
    public let id: String
    public let value: String
    public let count: Int
    public var isSelected: Bool

    public init(value: String, count: Int, isSelected: Bool = true) {
        self.id = value
        self.value = value
        self.count = count
        self.isSelected = isSelected
    }
}

/// Search ドキュメント
public struct SearchDocument: Sendable {
    public var items: [SearchableItem]
    public var entityName: String
    public var searchFieldNames: [String]
    public var allFieldNames: [String]

    public init(
        items: [SearchableItem] = [],
        entityName: String = "",
        searchFieldNames: [String] = [],
        allFieldNames: [String] = []
    ) {
        self.items = items
        self.entityName = entityName
        self.searchFieldNames = searchFieldNames
        self.allFieldNames = allFieldNames
    }

    /// CatalogDataAccess の結果から構築
    public init(
        items: [[String: Any]],
        entityName: String,
        textFieldNames: [String]
    ) {
        self.entityName = entityName
        self.searchFieldNames = textFieldNames

        var allFields: Set<String> = []
        var searchableItems: [SearchableItem] = []

        for item in items {
            let id: String
            if let sid = item["id"] as? String { id = sid }
            else if let sid = item["_id"] as? String { id = sid }
            else { id = UUID().uuidString }

            var textFields: [String: String] = [:]
            var allFieldsDict: [String: String] = [:]

            for (key, value) in item {
                let strVal = String(describing: value)
                allFieldsDict[key] = strVal
                allFields.insert(key)
                if textFieldNames.contains(key) {
                    textFields[key] = strVal
                }
            }

            // テキストフィールドが指定されていない場合、String 型の値を全て対象にする
            if textFields.isEmpty {
                for (key, value) in item {
                    if value is String {
                        textFields[key] = value as? String ?? ""
                    }
                }
            }

            searchableItems.append(SearchableItem(
                id: id,
                textFields: textFields,
                allFields: allFieldsDict
            ))
        }

        self.items = searchableItems
        self.allFieldNames = allFields.sorted()
    }
}
