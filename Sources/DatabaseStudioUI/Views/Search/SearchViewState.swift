import SwiftUI

/// Owns Search Console state and search interactions.
@Observable @MainActor
final class SearchViewState {

    // MARK: - Document

    var document: SearchDocument

    // MARK: - Search Input

    var queryText: String = "" {
        didSet { scheduleSearchAfterQueryChange() }
    }
    var matchMode: SearchMatchMode = .all {
        didSet { executeSearch() }
    }

    // MARK: - Results

    private(set) var results: [SearchResult] = []
    private(set) var facets: [Facet] = []
    private(set) var searchDuration: TimeInterval = 0
    var selectedResultID: String?

    var selectedResult: SearchResult? {
        guard let id = selectedResultID else { return nil }
        return results.first { $0.id == id }
    }

    // MARK: - Facet Filters

    /// Toggles a facet value and reapplies the active filters.
    func toggleFacetValue(fieldName: String, value: String) {
        guard let facetIndex = facets.firstIndex(where: { $0.fieldName == fieldName }),
              let valueIndex = facets[facetIndex].values.firstIndex(where: { $0.value == value }) else {
            return
        }
        facets[facetIndex].values[valueIndex].isSelected.toggle()
        applyFacetFilters()
    }

    // MARK: - Search State

    private let searchIndex = BM25SearchIndex()
    private var pendingSearchTask: Task<Void, Never>?
    private var unfilteredResults: [SearchResult] = []

    // MARK: - Initialization

    init(document: SearchDocument, initialQuery: String = "") {
        self.document = document
        searchIndex.replaceItems(with: document.items)
        if !initialQuery.isEmpty {
            self.queryText = initialQuery
            executeSearch()
        }
    }

    // MARK: - Document Updates

    func updateDocument(_ newDocument: SearchDocument) {
        document = newDocument
        searchIndex.replaceItems(with: newDocument.items)
        if !queryText.isEmpty {
            executeSearch()
        }
    }

    // MARK: - Search Execution

    private func scheduleSearchAfterQueryChange() {
        pendingSearchTask?.cancel()
        pendingSearchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch is CancellationError {
                return
            } catch {
                preconditionFailure("Search scheduling failed: \(error)")
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

        unfilteredResults = searchIndex.search(
            query: queryText,
            mode: matchMode,
            limit: 200
        )

        let facetFieldNames = document.allFieldNames.filter { name in
            !document.searchFieldNames.contains(name) && name != "id" && name != "_id"
        }
        facets = searchIndex.facets(
            results: unfilteredResults,
            fieldNames: facetFieldNames,
            allItems: document.items
        )

        results = unfilteredResults
        searchDuration = CFAbsoluteTimeGetCurrent() - start
    }

    // MARK: - Facet Application

    private func applyFacetFilters() {
        var filtered = unfilteredResults

        for facet in facets {
            let selectedValues = Set(facet.values.filter(\.isSelected).map(\.value))
            guard !selectedValues.isEmpty, selectedValues.count < facet.values.count else { continue }
            filtered = filtered.filter { result in
                guard let value = result.item.allFields[facet.fieldName] else { return false }
                return selectedValues.contains(value)
            }
        }

        results = filtered
    }
}
