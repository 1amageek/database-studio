import SwiftUI
import AppKit
import Core

/// メインビュー（3ペイン構成 + Inspector）
public struct MainView: View {
    @State private var viewModel = AppViewModel()
    @State private var metricsViewModel: MetricsViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingConnectionSettings = false
    @State private var showInspector = false

    private var isConnectionRequired: Bool {
        if case .connected = viewModel.connectionState { return false }
        return true
    }

    public init() {
        let vm = AppViewModel()
        _viewModel = State(initialValue: vm)
        _metricsViewModel = State(initialValue: MetricsViewModel(metricsService: vm.metricsService))
    }

    private func restoreLastConnection() async {
        let historyService = ConnectionHistoryService.shared
        if let last = historyService.mostRecent {
            viewModel.filePath = last.filePath
            viewModel.rootDirectoryPath = last.rootDirectoryPath
            await viewModel.connect()
            if case .connected = viewModel.connectionState {
                historyService.addOrUpdate(
                    filePath: last.filePath,
                    rootDirectoryPath: last.rootDirectoryPath
                )
                return
            }
        }
        showingConnectionSettings = true
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // サイドバー: ディレクトリツリー + 接続状態
            VStack(spacing: 0) {
                DirectoryTreeView(viewModel: viewModel)

                Divider()

                ConnectionStatusBar(viewModel: viewModel, showSettings: $showingConnectionSettings)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } content: {
            // コンテンツ: Items テーブル
            ItemsContentView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
        } detail: {
            // 詳細: Item 詳細
            DetailPaneView(viewModel: viewModel)
        }
        .navigationTitle("Database Studio")
        .inspector(isPresented: $showInspector) {
            InspectorPaneView(viewModel: viewModel, metricsViewModel: metricsViewModel)
                .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Inspector")
                .keyboardShortcut("i", modifiers: [.option, .command])
            }
        }
        .task {
            await restoreLastConnection()
        }
        .sheet(isPresented: $showingConnectionSettings) {
            ConnectionSettingsView(viewModel: viewModel, isRequired: isConnectionRequired)
        }
        .interactiveDismissDisabled(isConnectionRequired)
    }
}

/// Detail ペイン（Item 詳細）
struct DetailPaneView: View {
    let viewModel: AppViewModel

    var body: some View {
        if let item = viewModel.selectedItem {
            ItemDetailView(item: item, viewModel: viewModel)
        } else if viewModel.selectedEntityName != nil {
            ContentUnavailableView(
                "Itemを選択",
                systemImage: "doc.text",
                description: Text("テーブルからItemを選択すると詳細が表示されます")
            )
        } else {
            ContentUnavailableView(
                "Typeを選択",
                systemImage: "cube.box",
                description: Text("サイドバーからTypeを選択してください")
            )
        }
    }
}

/// Item 詳細ビュー（JSONビューア）
struct ItemDetailView: View {
    let item: DecodedItem
    let viewModel: AppViewModel
    @State private var copied = false
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // ヘッダー
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.id)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)

                        Spacer()

                        Button {
                            copyJSON()
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copied = false
                            }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy JSON")
                    }

                    HStack {
                        Label(item.typeName, systemImage: "cube.box.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(item.formattedSize)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

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
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                // JSON データ
                GroupBox("Data") {
                    JSONView(json: item.fields)
                }
            }
            .padding()
        }
        .navigationTitle(item.id)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit")
                .keyboardShortcut("e", modifiers: .command)

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete")
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
        .sheet(isPresented: $showingEditor) {
            ItemEditorView(
                mode: .edit(item),
                typeName: item.typeName,
                onSave: { id, json in
                    try await viewModel.updateItem(id: id, json: json)
                },
                onCancel: {
                    showingEditor = false
                }
            )
        }
        .alert("Delete Item?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await viewModel.deleteItem(id: item.id)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func copyJSON() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.prettyJSON, forType: .string)
    }
}

/// JSON表示ビュー（再帰的ツリー構造）
struct JSONView: View {
    let json: [String: Any]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(json.keys.sorted(), id: \.self) { key in
                JSONKeyValueView(key: key, value: json[key], depth: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// JSON キー・バリューペアの表示
struct JSONKeyValueView: View {
    let key: String
    let value: Any?
    let depth: Int

    @State private var isExpanded = true

    private var indent: CGFloat {
        CGFloat(depth) * 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 4) {
                // インデント
                if depth > 0 {
                    Color.clear.frame(width: indent)
                }

                // 展開/折りたたみボタン（ネスト構造の場合）
                if isExpandable {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12)
                }

                // キー
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)

                Text(":")
                    .foregroundStyle(.secondary)

                // 値（プリミティブまたはサマリー）
                if !isExpandable {
                    JSONPrimitiveValueView(value: value)
                } else if !isExpanded {
                    // 折りたたみ時のサマリー
                    Text(collapsedSummary)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // 展開時の子要素
            if isExpandable && isExpanded {
                JSONNestedContentView(value: value, depth: depth + 1)
            }
        }
    }

    private var isExpandable: Bool {
        if let dict = value as? [String: Any], !dict.isEmpty {
            return true
        }
        if let array = value as? [Any], !array.isEmpty {
            return true
        }
        return false
    }

    private var collapsedSummary: String {
        if let dict = value as? [String: Any] {
            return "{ \(dict.count) fields }"
        }
        if let array = value as? [Any] {
            return "[ \(array.count) items ]"
        }
        return ""
    }
}

/// ネストしたコンテンツの表示
struct JSONNestedContentView: View {
    let value: Any?
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let dict = value as? [String: Any] {
                ForEach(dict.keys.sorted(), id: \.self) { key in
                    JSONKeyValueView(key: key, value: dict[key], depth: depth)
                }
            } else if let array = value as? [Any] {
                ForEach(Array(array.enumerated()), id: \.offset) { index, element in
                    JSONArrayElementView(index: index, value: element, depth: depth)
                }
            }
        }
    }
}

/// 配列要素の表示
struct JSONArrayElementView: View {
    let index: Int
    let value: Any
    let depth: Int

    @State private var isExpanded = true

    private var indent: CGFloat {
        CGFloat(depth) * 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 4) {
                // インデント
                Color.clear.frame(width: indent)

                // 展開/折りたたみボタン
                if isExpandable {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12)
                }

                // インデックス
                Text("[\(index)]")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.purple)

                // 値（プリミティブまたはサマリー）
                if !isExpandable {
                    JSONPrimitiveValueView(value: value)
                } else if !isExpanded {
                    Text(collapsedSummary)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // 展開時の子要素
            if isExpandable && isExpanded {
                JSONNestedContentView(value: value, depth: depth + 1)
            }
        }
    }

    private var isExpandable: Bool {
        if let dict = value as? [String: Any], !dict.isEmpty {
            return true
        }
        if let array = value as? [Any], !array.isEmpty {
            return true
        }
        return false
    }

    private var collapsedSummary: String {
        if let dict = value as? [String: Any] {
            return "{ \(dict.count) fields }"
        }
        if let array = value as? [Any] {
            return "[ \(array.count) items ]"
        }
        return ""
    }
}

/// プリミティブ値の表示
struct JSONPrimitiveValueView: View {
    let value: Any?

    var body: some View {
        Text(formattedValue)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(valueColor)
            .textSelection(.enabled)
    }

    private var formattedValue: String {
        guard let value = value else { return "null" }

        if value is NSNull {
            return "null"
        } else if let str = value as? String {
            return "\"\(str)\""
        } else if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue ? "true" : "false"
            }
            return "\(num)"
        } else if let array = value as? [Any] {
            if array.isEmpty {
                return "[]"
            }
            return "[ \(array.count) items ]"
        } else if let dict = value as? [String: Any] {
            if dict.isEmpty {
                return "{}"
            }
            return "{ \(dict.count) fields }"
        } else {
            return String(describing: value)
        }
    }

    private var valueColor: Color {
        guard let value = value else { return .orange }

        if value is NSNull {
            return .orange
        } else if value is String {
            return .green
        } else if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .orange
            }
            return .cyan
        } else {
            return .primary
        }
    }
}

/// Inspector ペイン（Indexes + Statistics + Schema）
struct InspectorPaneView: View {
    let viewModel: AppViewModel
    let metricsViewModel: MetricsViewModel
    @State private var showSchemaVisualization = false
    @State private var showDataStatistics = false
    @State private var showMetricsDashboard = false

    var body: some View {
        if let entity = viewModel.selectedEntity {
            List {
                // Collection Statistics
                if let stats = viewModel.currentCollectionStats {
                    Section("Statistics") {
                        CollectionStatsView(stats: stats)
                    }
                }

                // Indexes from Schema.Entity
                Section("Indexes (\(entity.indexes.count))") {
                    ForEach(entity.indexes, id: \.name) { index in
                        IndexRowCompact(index: index)
                    }
                }

                // Entity Fields
                Section("Fields (\(entity.fields.count))") {
                    ForEach(entity.fields, id: \.name) { field in
                        HStack {
                            Text(field.name)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(field.type.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Directory Path
                Section("Directory") {
                    Text(entity.directoryPathDisplay)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Analysis Actions
                Section("Analysis") {
                    Button {
                        showSchemaVisualization = true
                    } label: {
                        Label("Schema Visualization", systemImage: "rectangle.3.group")
                    }

                    Button {
                        showDataStatistics = true
                    } label: {
                        Label("Data Statistics", systemImage: "chart.pie")
                    }

                    Button {
                        showMetricsDashboard = true
                    } label: {
                        Label("Performance Metrics", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
            }
            .listStyle(.sidebar)
            .sheet(isPresented: $showSchemaVisualization) {
                SchemaVisualizationView(entity: entity)
            }
            .sheet(isPresented: $showDataStatistics) {
                DataStatisticsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showMetricsDashboard) {
                MetricsDashboardView(viewModel: metricsViewModel)
            }
        } else {
            ContentUnavailableView(
                "No Entity Selected",
                systemImage: "info.circle",
                description: Text("Select an entity from the sidebar")
            )
        }
    }
}

/// サイドバー下部の接続状態バー
struct ConnectionStatusBar: View {
    let viewModel: AppViewModel
    @Binding var showSettings: Bool

    var body: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 6) {
                switch viewModel.connectionState {
                case .disconnected:
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                    Text("Not Connected")
                        .foregroundStyle(.secondary)

                case .connecting:
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Connecting...")
                        .foregroundStyle(.secondary)

                case .connected:
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.green)
                    Text((viewModel.filePath as NSString).lastPathComponent)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                case .error:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Connection Error")
                        .foregroundStyle(.red)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Main View - With Inspector") {
    @Previewable @State var viewModel = AppViewModel.preview(
        connectionState: .connected,
        entityTree: PreviewData.entityTree,
        selectedEntityName: "User",
        items: PreviewData.userItems,
        selectedItemID: "user_001",
        itemsProvider: PreviewData.items(for:),
        collectionStats: PreviewData.userCollectionStats
    )
    @Previewable @State var columnVisibility: NavigationSplitViewVisibility = .all
    @Previewable @State var showInspector = true

    NavigationSplitView(columnVisibility: $columnVisibility) {
        DirectoryTreeView(viewModel: viewModel)
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
    } content: {
        ItemsContentView(viewModel: viewModel)
            .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
    } detail: {
        DetailPaneView(viewModel: viewModel)
            .inspector(isPresented: $showInspector) {
                InspectorPaneView(viewModel: viewModel, metricsViewModel: MetricsViewModel(metricsService: viewModel.metricsService))
                    .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
            }
    }
    .navigationTitle("Database Studio")
    .frame(width: 1400, height: 700)
}

#Preview("Detail Pane - User") {
    @Previewable @State var viewModel = AppViewModel.preview(
        connectionState: .connected,
        entityTree: PreviewData.entityTree,
        selectedEntityName: "User",
        items: PreviewData.userItems,
        selectedItemID: "user_001",
        itemsProvider: PreviewData.items(for:)
    )
    DetailPaneView(viewModel: viewModel)
        .frame(width: 500, height: 600)
}

#Preview("Inspector Pane") {
    @Previewable @State var viewModel = AppViewModel.preview(
        connectionState: .connected,
        entityTree: PreviewData.entityTree,
        selectedEntityName: "User",
        itemsProvider: PreviewData.items(for:),
        collectionStats: PreviewData.userCollectionStats
    )
    InspectorPaneView(viewModel: viewModel, metricsViewModel: MetricsViewModel(metricsService: viewModel.metricsService))
        .frame(width: 300, height: 500)
}
