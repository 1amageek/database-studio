import SwiftUI
import AppKit
import Core

/// Items テーブルビュー（中央ペイン）- 選択されたTypeのItemsを表示
struct ItemsContentView: View {
    let studioState: DatabaseStudioState

    var body: some View {
        if let typeName = studioState.selectedEntityName {
            ItemsTableView(typeName: typeName, studioState: studioState)
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
    let studioState: DatabaseStudioState
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var searchMode: SearchMode = .all
    @State private var showingQueryBuilder = false
    @State private var showingColumnConfig = false
    @State private var showingCreateEditor = false
    @State private var showingImportView = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var sortOrder: [KeyPathComparator<StudioRecord>] = [
        KeyPathComparator(\.id, order: .forward)
    ]
    @State private var selectedIDs: Set<String> = []
    @State private var columnConfig: ColumnConfig = .initialConfiguration

    private var filteredItems: [StudioRecord] {
        // First apply query filter
        var items = QueryExecutor.filter(studioState.currentItems, with: studioState.currentQuery)
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
    private func searchInJSON(_ fields: [String: Any], for searchText: String) -> Bool {
        for (_, value) in fields {
            if let string = value as? String, string.lowercased().contains(searchText) {
                return true
            } else if let number = value as? NSNumber {
                if String(describing: number).contains(searchText) {
                    return true
                }
            } else if let nested = value as? [String: Any] {
                if searchInJSON(nested, for: searchText) {
                    return true
                }
            } else if let array = value as? [Any] {
                for element in array {
                    if let string = element as? String, string.lowercased().contains(searchText) {
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

    private var selectedItems: [StudioRecord] {
        filteredItems.filter { selectedIDs.contains($0.id) }
    }

    // JSON field columns (up to four additional columns)
    private var jsonField0: String? { columnConfig.jsonFieldColumns.indices.contains(0) ? columnConfig.jsonFieldColumns[0] : nil }
    private var jsonField1: String? { columnConfig.jsonFieldColumns.indices.contains(1) ? columnConfig.jsonFieldColumns[1] : nil }
    private var jsonField2: String? { columnConfig.jsonFieldColumns.indices.contains(2) ? columnConfig.jsonFieldColumns[2] : nil }
    private var jsonField3: String? { columnConfig.jsonFieldColumns.indices.contains(3) ? columnConfig.jsonFieldColumns[3] : nil }

    var body: some View {
        if studioState.isLoadingItems {
            ProgressView("読み込み中...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let failureMessage = studioState.databaseOperationFailureMessage {
            ContentUnavailableView(
                "Record Access Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(failureMessage)
            )
        } else if studioState.currentItems.isEmpty {
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

                    if studioState.currentQuery.hasConditions {
                        HStack(spacing: 2) {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .font(.caption2)
                            Text("\(studioState.currentQuery.conditionCount)")
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
                                .onAppear {
                                    if item.id == filteredItems.last?.id {
                                        Task { await studioState.loadMoreItems() }
                                    }
                                }
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
                        TableColumn("Size", value: \.jsonByteCount) { item in
                            Text(item.formattedJSONSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 60, ideal: 80, max: 100)
                    }
                }
                .tableStyle(.inset)
                .onChange(of: selectedIDs) { _, newValue in
                    studioState.selectItems(ids: newValue)
                }

                // 追加読み込みインジケーター
                if studioState.isLoadingMoreItems {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(.bar)
                }
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
                        try await studioState.createItem(id: id, fields: json)
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
                        try await studioState.importItems(records: records)
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
                            try await studioState.deleteItems(ids: Array(selectedIDs))
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
                        Image(systemName: studioState.currentQuery.hasConditions
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                    .help("Filter")
                    .keyboardShortcut("f", modifiers: .option)
                    .popover(isPresented: $showingQueryBuilder) {
                        QueryBuilderView(
                            query: Binding(
                                get: { studioState.currentQuery },
                                set: { studioState.currentQuery = $0 }
                            ),
                            availableFields: studioState.discoveredFields,
                            typeName: typeName,
                            onApply: {
                                showingQueryBuilder = false
                            },
                            onClear: {
                                studioState.clearQuery()
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
                            availableFields: studioState.discoveredFields
                        )
                    }
                }

                // コレクション操作
                ToolbarItemGroup(placement: .primaryAction) {
                    // Graph ウィンドウを開く（Graph インデックスがある場合のみ）
                    if let graphIndex = studioState.selectedEntity?.indexes.first(where: { $0.kind.identifier == "graph" }) {
                        Button { [studioState] in
                            let windowState = GraphWindowState.shared
                            windowState.document = nil
                            windowState.loadFailureMessage = nil
                            windowState.isLoading = true
                            windowState.entityName = typeName
                            windowState.loadDocument = { [weak studioState] in
                                guard let studioState else { throw StudioError.databaseSessionUnavailable }
                                let items = try await studioState.loadAllItems(for: typeName)
                                var graphDocument = try GraphDocument(
                                    records: items,
                                    graphIndex: graphIndex
                                )
                                if let ontology = try await studioState.loadOntology() {
                                    graphDocument.mergeOntology(ontology)
                                }
                                return graphDocument
                            }
                            windowState.refreshDocument = windowState.loadDocument
                            openWindow(id: "graph-viewer")
                        } label: {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                        }
                        .help("Open Graph")
                    }

                    // Map ウィンドウを開く（spatial インデックスまたは lat/lng フィールドがある場合）
                    if let spatialIndex = studioState.selectedEntity?.indexes.first(where: { $0.kind.identifier == "spatial" }) {
                        Button { [studioState] in
                            Task {
                                do {
                                    let records = try await studioState.loadAllItems(for: typeName)
                                    let latitudeField = spatialIndex.kind.fieldNames.first ?? "latitude"
                                    let longitudeField = spatialIndex.kind.fieldNames.count > 1 ? spatialIndex.kind.fieldNames[1] : "longitude"
                                    let mapState = MapWindowState.shared
                                    mapState.document = MapDocument(
                                        items: records.map(\.fields),
                                        entityName: typeName,
                                        latitudeField: latitudeField,
                                        longitudeField: longitudeField
                                    )
                                    mapState.entityName = typeName
                                    mapState.refreshDocument = { [weak studioState] in
                                        guard let studioState else { throw StudioError.databaseSessionUnavailable }
                                        let records = try await studioState.loadAllItems(for: typeName)
                                        return MapDocument(
                                            items: records.map(\.fields),
                                            entityName: typeName,
                                            latitudeField: latitudeField,
                                            longitudeField: longitudeField
                                        )
                                    }
                                    openWindow(id: "map-view")
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            Image(systemName: "map")
                        }
                        .help("Open Map")
                    }

                    // Search Console を開く（fulltext インデックスがある場合）
                    if let fulltextIndex = studioState.selectedEntity?.indexes.first(where: { $0.kind.identifier == "fulltext" }) {
                        Button { [studioState] in
                            Task {
                                do {
                                    let records = try await studioState.loadAllItems(for: typeName)
                                    let searchState = SearchWindowState.shared
                                    searchState.document = SearchDocument(
                                        items: records.map(\.fields),
                                        entityName: typeName,
                                        textFieldNames: fulltextIndex.kind.fieldNames
                                    )
                                    searchState.entityName = typeName
                                    searchState.refreshDocument = { [weak studioState] in
                                        guard let studioState else { throw StudioError.databaseSessionUnavailable }
                                        let records = try await studioState.loadAllItems(for: typeName)
                                        return SearchDocument(
                                            items: records.map(\.fields),
                                            entityName: typeName,
                                            textFieldNames: fulltextIndex.kind.fieldNames
                                        )
                                    }
                                    openWindow(id: "search-console")
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .help("Open Search Console")
                    }

                    // Vector Explorer を開く（vector インデックスがある場合）
                    if let vectorIndex = studioState.selectedEntity?.indexes.first(where: { $0.kind.identifier == "vector" }) {
                        Button { [studioState] in
                            Task {
                                do {
                                    let records = try await studioState.loadAllItems(for: typeName)
                                    let embeddingField = vectorIndex.kind.fieldNames.first ?? "embedding"
                                    let vectorState = VectorWindowState.shared
                                    vectorState.document = try VectorDocument(
                                        records: records,
                                        entityName: typeName,
                                        embeddingField: embeddingField
                                    )
                                    vectorState.entityName = typeName
                                    vectorState.refreshDocument = { [weak studioState] in
                                        guard let studioState else { throw StudioError.databaseSessionUnavailable }
                                        let records = try await studioState.loadAllItems(for: typeName)
                                        return try VectorDocument(
                                            records: records,
                                            entityName: typeName,
                                            embeddingField: embeddingField
                                        )
                                    }
                                    openWindow(id: "vector-explorer")
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            Image(systemName: "cube.transparent")
                        }
                        .help("Open Vector Explorer")
                    }

                    // Analytics ダッシュボード（常時表示）
                    Button { [studioState] in
                        Task {
                            do {
                                let records = try await studioState.loadAllItems(for: typeName)
                                let analyticsState = AnalyticsWindowState.shared
                                analyticsState.document = AnalyticsDocument(
                                    items: records.map(\.fields),
                                    entityName: typeName
                                )
                                analyticsState.entityName = typeName
                                analyticsState.refreshDocument = { [weak studioState] in
                                    guard let studioState else { throw StudioError.databaseSessionUnavailable }
                                    let records = try await studioState.loadAllItems(for: typeName)
                                    return AnalyticsDocument(
                                        items: records.map(\.fields),
                                        entityName: typeName
                                    )
                                }
                                openWindow(id: "analytics-dashboard")
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Image(systemName: "chart.bar")
                    }
                    .help("Open Analytics")

                    // 一括操作メニュー（選択時 or Import/Export）
                    Menu {
                        Button {
                            showingImportView = true
                        } label: {
                            Label("Import...", systemImage: "square.and.arrow.down")
                        }

                        Menu("Export") {
                            Button("JSON") { exportItems(format: .json) }
                            Button("JSONL") { exportItems(format: .jsonLines) }
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
                                Label("Copy Selected IDs", systemImage: "graphDocument.on.graphDocument")
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
                            if let entityName = studioState.selectedEntityName {
                                await studioState.loadItems(for: entityName)
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

    // MARK: - Export

    private func exportItems(format: RecordExportFormat) {
        do {
            try RecordExporter.exportToSelectedDestination(
                records: filteredItems,
                typeName: typeName,
                format: format,
                fields: studioState.discoveredFields
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportSelectedItems(format: RecordExportFormat) {
        guard !selectedItems.isEmpty else { return }
        do {
            try RecordExporter.exportToSelectedDestination(
                records: selectedItems,
                typeName: "\(typeName)_selected",
                format: format,
                fields: studioState.discoveredFields
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copySelectedIDs() {
        guard !selectedIDs.isEmpty else { return }
        let ids = selectedIDs.sorted().joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ids, forType: .string)
    }

    // MARK: - Item Preview Formatting

    private func jsonPreview(_ fields: [String: Any]) -> String {
        let keys = fields.keys.sorted().prefix(3)
        let preview = keys.map { key in
            let value = fields[key]
            let valueText: String
            if let string = value as? String {
                valueText = "\"\(string)\""
            } else if let number = value as? NSNumber {
                valueText = "\(number)"
            } else {
                valueText = "..."
            }
            return "\(key): \(valueText)"
        }.joined(separator: ", ")
        return "{ \(preview)\(fields.count > 3 ? ", ..." : "") }"
    }
}

// MARK: - Previews

#Preview("Items Table - User") {
    @Previewable @State var studioState = DatabaseStudioState.sample(
        connectionState: .connected,
        entityTree: StudioSampleData.entityTree,
        selectedEntityName: "User",
        records: StudioSampleData.userRecords,
        recordsProvider: StudioSampleData.records(for:)
    )
    ItemsContentView(studioState: studioState)
        .frame(width: 500, height: 400)
}

#Preview("Items Table - Empty") {
    @Previewable @State var studioState = DatabaseStudioState.sample(
        connectionState: .connected,
        entityTree: StudioSampleData.entityTree,
        selectedEntityName: "User",
        records: []
    )
    ItemsContentView(studioState: studioState)
        .frame(width: 500, height: 400)
}

#Preview("No Type Selected") {
    @Previewable @State var studioState = DatabaseStudioState.sample(
        connectionState: .connected,
        entityTree: StudioSampleData.entityTree,
        selectedEntityName: nil,
        recordsProvider: StudioSampleData.records(for:)
    )
    ItemsContentView(studioState: studioState)
        .frame(width: 500, height: 400)
}
