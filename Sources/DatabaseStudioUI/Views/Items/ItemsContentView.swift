import SwiftUI
import AppKit
import Core

/// Items テーブルビュー（中央ペイン）- 選択されたTypeのItemsを表示
struct ItemsContentView: View {
    let viewModel: AppViewModel

    var body: some View {
        if let typeName = viewModel.selectedEntityName {
            ItemsTableView(typeName: typeName, viewModel: viewModel)
                .navigationTitle(typeName)
        } else {
            ContentUnavailableView(
                "Typeを選択",
                systemImage: "cube.box",
                description: Text("サイドバーからTypeを選択するとアイテム一覧が表示されます")
            )
        }
    }
}

/// 検索モード
enum SearchMode: String, CaseIterable {
    case id = "ID"
    case all = "All Fields"
}

/// Items テーブルビュー
struct ItemsTableView: View {
    let typeName: String
    let viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var searchMode: SearchMode = .all
    @State private var showingQueryBuilder = false
    @State private var showingColumnConfig = false
    @State private var showingCreateEditor = false
    @State private var showingImportView = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var sortOrder: [KeyPathComparator<DecodedItem>] = [
        KeyPathComparator(\.id, order: .forward)
    ]
    @State private var selectedIDs: Set<String> = []
    @State private var columnConfig: ColumnConfig = .default

    private var filteredItems: [DecodedItem] {
        // First apply query filter
        var items = QueryExecutor.filter(viewModel.currentItems, with: viewModel.currentQuery)
        // Then apply search filter
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            items = items.filter { item in
                switch searchMode {
                case .id:
                    return item.id.localizedCaseInsensitiveContains(searchText)
                case .all:
                    // Search in ID
                    if item.id.localizedCaseInsensitiveContains(searchText) {
                        return true
                    }
                    // Search in fields
                    return searchInJSON(item.fields, for: searchLower)
                }
            }
        }
        // Apply sorting
        items.sort(using: sortOrder)
        return items
    }

    /// Recursively search for text in JSON structure
    private func searchInJSON(_ json: [String: Any], for searchText: String) -> Bool {
        for (_, value) in json {
            if let str = value as? String, str.lowercased().contains(searchText) {
                return true
            } else if let num = value as? NSNumber {
                if String(describing: num).contains(searchText) {
                    return true
                }
            } else if let nested = value as? [String: Any] {
                if searchInJSON(nested, for: searchText) {
                    return true
                }
            } else if let array = value as? [Any] {
                for element in array {
                    if let str = element as? String, str.lowercased().contains(searchText) {
                        return true
                    } else if let nested = element as? [String: Any] {
                        if searchInJSON(nested, for: searchText) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private var selectedItems: [DecodedItem] {
        filteredItems.filter { selectedIDs.contains($0.id) }
    }

    // JSON field column helpers (max 4 extra columns)
    private var jsonField0: String? { columnConfig.jsonFieldColumns.indices.contains(0) ? columnConfig.jsonFieldColumns[0] : nil }
    private var jsonField1: String? { columnConfig.jsonFieldColumns.indices.contains(1) ? columnConfig.jsonFieldColumns[1] : nil }
    private var jsonField2: String? { columnConfig.jsonFieldColumns.indices.contains(2) ? columnConfig.jsonFieldColumns[2] : nil }
    private var jsonField3: String? { columnConfig.jsonFieldColumns.indices.contains(3) ? columnConfig.jsonFieldColumns[3] : nil }

    var body: some View {
        if viewModel.isLoadingItems {
            ProgressView("読み込み中...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.currentItems.isEmpty {
            ContentUnavailableView(
                "アイテムがありません",
                systemImage: "tray",
                description: Text("\(typeName) のデータがありません")
            )
        } else {
            VStack(spacing: 0) {
                // ステータスバー（件数・選択情報のみ - シンプルに）
                HStack(spacing: 8) {
                    Text("\(filteredItems.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if viewModel.currentQuery.hasConditions {
                        HStack(spacing: 2) {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .font(.caption2)
                            Text("\(viewModel.currentQuery.conditionCount)")
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }

                    if !selectedIDs.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("\(selectedIDs.count) selected")
                        }
                        .font(.caption)
                        .foregroundStyle(.tint)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.bar)

                // エラーメッセージ
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                        Spacer()
                        Button {
                            errorMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                }

                // テーブル（複数選択・ソート対応・カラム設定対応）
                Table(filteredItems, selection: $selectedIDs, sortOrder: $sortOrder) {
                    // ID Column
                    if columnConfig.visibleColumns.contains(.id) {
                        TableColumn("ID", value: \.id) { item in
                            Text(item.id)
                                .font(.system(.body, design: .monospaced))
                        }
                        .width(min: 100, ideal: 150, max: 250)
                    }

                    // Preview Column
                    if columnConfig.visibleColumns.contains(.preview) {
                        TableColumn("Preview") { item in
                            Text(jsonPreview(item.fields))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .width(min: 200, ideal: 300)
                    }

                    // JSON Field Columns (up to 4)
                    if let field0 = jsonField0 {
                        TableColumn(field0) { item in
                            Text(item.jsonValue(at: field0))
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                        .width(min: 80, ideal: 120, max: 200)
                    }
                    if let field1 = jsonField1 {
                        TableColumn(field1) { item in
                            Text(item.jsonValue(at: field1))
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                        .width(min: 80, ideal: 120, max: 200)
                    }
                    if let field2 = jsonField2 {
                        TableColumn(field2) { item in
                            Text(item.jsonValue(at: field2))
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                        .width(min: 80, ideal: 120, max: 200)
                    }
                    if let field3 = jsonField3 {
                        TableColumn(field3) { item in
                            Text(item.jsonValue(at: field3))
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                        .width(min: 80, ideal: 120, max: 200)
                    }

                    // Size Column
                    if columnConfig.visibleColumns.contains(.size) {
                        TableColumn("Size", value: \.rawSize) { item in
                            Text(item.formattedSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 60, ideal: 80, max: 100)
                    }
                }
                .tableStyle(.inset)
                .onChange(of: selectedIDs) { _, newValue in
                    viewModel.selectItems(ids: newValue)
                }

                // ページネーションフッター
                paginationFooter
            }
            .searchable(text: $searchText, prompt: searchMode == .id ? "Search by ID" : "Search all fields")
            .searchScopes($searchMode) {
                ForEach(SearchMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .sheet(isPresented: $showingCreateEditor) {
                ItemEditorView(
                    mode: .create,
                    typeName: typeName,
                    onSave: { id, json in
                        try await viewModel.createItem(id: id, json: json)
                    },
                    onCancel: {
                        showingCreateEditor = false
                    }
                )
            }
            .sheet(isPresented: $showingImportView) {
                ImportView(
                    typeName: typeName,
                    onImport: { records in
                        try await viewModel.importItems(records: records)
                    },
                    onCancel: {
                        showingImportView = false
                    }
                )
            }
            .alert("Delete \(selectedIDs.count) Items?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await viewModel.deleteItems(ids: Array(selectedIDs))
                            selectedIDs.removeAll()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .toolbar {
                // 表示制御
                ToolbarItemGroup(placement: .secondaryAction) {
                    Button {
                        showingQueryBuilder = true
                    } label: {
                        Image(systemName: viewModel.currentQuery.hasConditions
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                    .help("Filter")
                    .keyboardShortcut("f", modifiers: .option)
                    .popover(isPresented: $showingQueryBuilder) {
                        QueryBuilderView(
                            query: Binding(
                                get: { viewModel.currentQuery },
                                set: { viewModel.currentQuery = $0 }
                            ),
                            availableFields: viewModel.discoveredFields,
                            typeName: typeName,
                            onApply: {
                                showingQueryBuilder = false
                            },
                            onClear: {
                                viewModel.clearQuery()
                            }
                        )
                    }

                    Button {
                        showingColumnConfig = true
                    } label: {
                        Image(systemName: "tablecells")
                    }
                    .help("Columns")
                    .popover(isPresented: $showingColumnConfig) {
                        ColumnConfigurationView(
                            config: $columnConfig,
                            availableFields: viewModel.discoveredFields
                        )
                    }
                }

                // コレクション操作
                ToolbarItemGroup(placement: .primaryAction) {
                    // Graph ウィンドウを開く（Graph インデックスがある場合のみ）
                    if let graphIndex = viewModel.selectedEntity?.indexes.first(where: { $0.kind.identifier == "graph" }) {
                        Button {
                            Task {
                                let allItems = await viewModel.loadAllItems(for: typeName)
                                let windowState = GraphWindowState.shared
                                windowState.document = GraphDocument(
                                    items: allItems,
                                    graphIndex: graphIndex
                                )
                                windowState.entityName = typeName
                                windowState.refreshAction = { [weak viewModel] in
                                    guard let viewModel else { return nil }
                                    let items = await viewModel.loadAllItems(for: typeName)
                                    return GraphDocument(
                                        items: items,
                                        graphIndex: graphIndex
                                    )
                                }
                                openWindow(id: "graph-viewer")
                            }
                        } label: {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                        }
                        .help("Open Graph")
                    }

                    // 一括操作メニュー（選択時 or Import/Export）
                    Menu {
                        Button {
                            showingImportView = true
                        } label: {
                            Label("Import...", systemImage: "square.and.arrow.down")
                        }

                        Menu("Export") {
                            Button("JSON") { exportItems(format: .json) }
                            Button("JSONL") { exportItems(format: .jsonl) }
                            Button("CSV") { exportItems(format: .csv) }
                        }

                        if !selectedIDs.isEmpty {
                            Divider()

                            Button {
                                exportSelectedItems(format: .json)
                            } label: {
                                Label("Export Selected (\(selectedIDs.count))", systemImage: "square.and.arrow.up")
                            }

                            Button {
                                copySelectedIDs()
                            } label: {
                                Label("Copy Selected IDs", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete Selected (\(selectedIDs.count))", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help("Actions")

                    Button {
                        showingCreateEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New Item")
                    .keyboardShortcut("n", modifiers: .command)

                    Button {
                        Task {
                            if let entityName = viewModel.selectedEntityName {
                                await viewModel.loadItems(for: entityName)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
    }

    // MARK: - Pagination Footer

    @ViewBuilder
    private var paginationFooter: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await viewModel.loadPreviousPage()
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.hasPreviousPage || viewModel.isLoadingItems)

            Text(viewModel.pageInfoText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                Task {
                    await viewModel.loadNextPage()
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.hasMoreItems || viewModel.isLoadingItems)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Export

    private func exportItems(format: ExportFormat) {
        let success = ExportService.exportAndSave(
            items: filteredItems,
            typeName: typeName,
            format: format,
            fields: viewModel.discoveredFields
        )
        if success {
            print("Export completed successfully")
        }
    }

    private func exportSelectedItems(format: ExportFormat) {
        guard !selectedItems.isEmpty else { return }
        let success = ExportService.exportAndSave(
            items: selectedItems,
            typeName: "\(typeName)_selected",
            format: format,
            fields: viewModel.discoveredFields
        )
        if success {
            print("Export \(selectedItems.count) selected items completed")
        }
    }

    private func copySelectedIDs() {
        guard !selectedIDs.isEmpty else { return }
        let ids = selectedIDs.sorted().joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ids, forType: .string)
    }

    // MARK: - Helpers

    private func jsonPreview(_ json: [String: Any]) -> String {
        let keys = json.keys.sorted().prefix(3)
        let preview = keys.map { key in
            let value = json[key]
            let valueStr: String
            if let str = value as? String {
                valueStr = "\"\(str)\""
            } else if let num = value as? NSNumber {
                valueStr = "\(num)"
            } else {
                valueStr = "..."
            }
            return "\(key): \(valueStr)"
        }.joined(separator: ", ")
        return "{ \(preview)\(json.count > 3 ? ", ..." : "") }"
    }
}

// MARK: - Previews

#Preview("Items Table - User") {
    @Previewable @State var viewModel = AppViewModel.preview(
        connectionState: .connected,
        entityTree: PreviewData.entityTree,
        selectedEntityName: "User",
        items: PreviewData.userItems,
        itemsProvider: PreviewData.items(for:)
    )
    ItemsContentView(viewModel: viewModel)
        .frame(width: 500, height: 400)
}

#Preview("Items Table - Empty") {
    @Previewable @State var viewModel = AppViewModel.preview(
        connectionState: .connected,
        entityTree: PreviewData.entityTree,
        selectedEntityName: "User",
        items: []
    )
    ItemsContentView(viewModel: viewModel)
        .frame(width: 500, height: 400)
}

#Preview("No Type Selected") {
    @Previewable @State var viewModel = AppViewModel.preview(
        connectionState: .connected,
        entityTree: PreviewData.entityTree,
        selectedEntityName: nil,
        itemsProvider: PreviewData.items(for:)
    )
    ItemsContentView(viewModel: viewModel)
        .frame(width: 500, height: 400)
}
