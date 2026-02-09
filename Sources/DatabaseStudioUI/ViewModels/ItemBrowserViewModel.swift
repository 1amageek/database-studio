import SwiftUI
import Observation

/// Itemブラウザ用ViewModel（AppViewModelに統合済みのため簡略化）
/// レガシー互換のためのラッパー
@MainActor
@Observable
public final class ItemBrowserViewModel {
    public var typeName: String = ""
    public private(set) var currentItems: [DecodedItem] = []
    public private(set) var isLoading = false
    public private(set) var error: String?

    @ObservationIgnored
    private let dataService: StudioDataService

    public init(dataService: StudioDataService) {
        self.dataService = dataService
    }

    public func loadItems(limit: Int = 100, offset: Int = 0) async {
        guard !typeName.isEmpty else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let allItems = try await dataService.findAll(typeName: typeName, limit: limit)
            currentItems = allItems.enumerated().map { index, dict -> DecodedItem in
                let id = dict["id"] as? String ?? "item_\(offset + index)"
                let data = (try? JSONSerialization.data(withJSONObject: dict, options: [])) ?? Data()
                return DecodedItem(
                    id: id,
                    typeName: typeName,
                    fields: dict,
                    rawSize: data.count
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func refresh() async {
        await loadItems()
    }
}
