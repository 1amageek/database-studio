import SwiftUI

/// Search Console の状態管理
@Observable @MainActor
final class SearchViewState {

    // MARK: - データ

    var document: SearchDocument

    // MARK: - 検索

    var queryText: String = "" {
        didSet { executeSearchDebounced() }
    }
    var matchMode: SearchMatchMode = .all {
        didSet { executeSearch() }
    }

    // MARK: - 結果

    private(set) var results: [SearchResult] = []
    private(set) var facets: [Facet] = []
    private(set) var searchDuration: TimeInterval = 0
    var selectedResultID: String?

    var selectedResult: SearchResult? {
        guard let id = selectedResultID else { return nil }
        return results.first { $0.id == id }
    }

    // MARK: - ファセットフィルタ

    /// ファセットの選択状態を変更
    func toggleFacetValue(fieldName: String, value: String) {
        guard let facetIndex = facets.firstIndex(where: { $0.fieldName == fieldName }),
              let valueIndex = facets[facetIndex].values.firstIndex(where: { $0.value == value }) else {
            return
        }
        facets[facetIndex].values[valueIndex].isSelected.toggle()
        applyFacetFilters()
    }

    // MARK: - 内部

    private let engine = BM25Engine()
    private var debounceTask: Task<Void, Never>?
    private var unfilteredResults: [SearchResult] = []

    // MARK: - 初期化

    init(document: SearchDocument, initialQuery: String = "") {
        self.document = document
        engine.buildIndex(from: document.items)
        if !initialQuery.isEmpty {
            self.queryText = initialQuery
            executeSearch()
        }
    }

    // MARK: - ドキュメント更新

    func updateDocument(_ newDocument: SearchDocument) {
        document = newDocument
        engine.buildIndex(from: newDocument.items)
        if !queryText.isEmpty {
            executeSearch()
        }
    }

    // MARK: - 検索実行

    private func executeSearchDebounced() {
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
            executeSearch()
        }
    }

    func executeSearch() {
        guard !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            unfilteredResults = []
            facets = []
            searchDuration = 0
            return
        }

        let start = CFAbsoluteTimeGetCurrent()

        unfilteredResults = engine.search(
            query: queryText,
            mode: matchMode,
            limit: 200
        )

        // ファセット計算
        let facetFieldNames = document.allFieldNames.filter { name in
            !document.searchFieldNames.contains(name) && name != "id" && name != "_id"
        }
        facets = engine.computeFacets(
            results: unfilteredResults,
            fieldNames: facetFieldNames,
            allItems: document.items
        )

        results = unfilteredResults
        searchDuration = CFAbsoluteTimeGetCurrent() - start
    }

    // MARK: - ファセットフィルタ適用

    private func applyFacetFilters() {
        var filtered = unfilteredResults

        for facet in facets {
            let selectedValues = Set(facet.values.filter(\.isSelected).map(\.value))
            // 何も選択されていない or 全て選択されている場合はフィルタしない
            guard !selectedValues.isEmpty, selectedValues.count < facet.values.count else { continue }
            filtered = filtered.filter { result in
                guard let value = result.item.allFields[facet.fieldName] else { return false }
                return selectedValues.contains(value)
            }
        }

        results = filtered
    }
}
