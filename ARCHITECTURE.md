# Database Studio - Architecture Design v6

database-frameworkのパラダイムを可視化するmacOS GUIアプリケーション。

## 設計思想

単なるデータブラウザではなく、**database-frameworkの構造全体を可視化**するツール。

- Directory階層の探索
- Persistable型とSchema情報
- 12種類のIndexKindと構造
- Subspace構造の可視化
- Index状態管理

---

## API理解

### database-framework/database-kit構造

```
database-kit (クライアント安全)
├── Persistable protocol
├── @Persistable macro
├── IndexKind (metadata)
└── Query types

database-framework (サーバー専用)
├── FDBContainer - リソース管理
├── FDBContext - 変更追跡・トランザクション
├── FDBDataStore - 低レベルストレージ
├── DirectoryLayer - ディレクトリ操作
└── Index実装 (12種類)
```

### 主要API

```swift
// 接続
let database = try FDBClient.openDatabase(clusterFilePath: path)

// トランザクション
try await database.withTransaction(configuration: .default) { transaction in
    // 値取得
    let value = try await transaction.getValue(for: key, snapshot: true)

    // 範囲取得
    for try await (key, value) in transaction.getRange(
        from: .firstGreaterOrEqual(begin),
        to: .firstGreaterOrEqual(end),
        snapshot: true
    ) { ... }
}

// DirectoryLayer
let layer = DirectoryLayer(database: database)
let names = try await layer.list(transaction: tx, path: ["app"])
let dir = try await layer.open(transaction: tx, path: ["app", "users"])
let subspace = dir?.subspace
```

### Subspace構造

```
[directory]/R/[typeName]/[id]           → Item
[directory]/I/[indexName]/[values]/[id] → Index entry
[directory]/S/...                       → Store metadata
[directory]/T/[indexName]               → Index state
[directory]/M/...                       → Metadata
[directory]/B/[keyRef]/[chunk]          → Blob chunks
```

---

## モジュール構成

```
Sources/
├── DatabaseStudioCore/        # ロジック層
│   ├── Connection/
│   │   └── DatabaseConnection.swift
│   ├── Explorer/
│   │   ├── DirectoryExplorer.swift
│   │   ├── SubspaceExplorer.swift
│   │   └── ItemExplorer.swift
│   ├── Inspector/
│   │   └── IndexInspector.swift
│   └── Models/
│       ├── DirectoryNode.swift
│       ├── SubspaceInfo.swift
│       ├── TypeInfo.swift
│       ├── IndexInfo.swift
│       ├── IndexKindIdentifier.swift
│       ├── IndexState.swift
│       └── ItemInfo.swift
├── DatabaseStudioUI/          # UI層
│   ├── App/
│   │   └── AppState.swift
│   ├── Views/
│   └── Components/
└── DatabaseStudio/            # エントリポイント
    └── DatabaseStudioApp.swift
```

---

## Core層設計

### 1. DatabaseConnection

```swift
import FoundationDB
import DatabaseEngine

/// FDB接続管理
public final class DatabaseConnection: Sendable {
    /// nonisolated(unsafe)でSendable問題を回避
    nonisolated(unsafe) public let database: any DatabaseProtocol

    public init(clusterFilePath: String) throws {
        self.database = try FDBClient.openDatabase(clusterFilePath: clusterFilePath)
    }

    /// トランザクション実行
    public func withTransaction<T: Sendable>(
        configuration: TransactionConfiguration = .default,
        _ operation: @Sendable (any TransactionProtocol) async throws -> T
    ) async throws -> T {
        try await database.withTransaction(configuration: configuration, operation)
    }
}
```

### 2. DirectoryExplorer

```swift
/// ディレクトリ探索
public struct DirectoryExplorer: Sendable {
    private let connection: DatabaseConnection

    public init(connection: DatabaseConnection) {
        self.connection = connection
    }

    /// 子ディレクトリ一覧
    public func listChildren(at path: [String]) async throws -> [DirectoryNode] {
        try await connection.withTransaction { transaction in
            let layer = DirectoryLayer(database: self.connection.database)
            let names = try await layer.list(transaction: transaction, path: path)
            return names.map { DirectoryNode(name: $0, path: path + [$0]) }
        }
    }

    /// Subspaceを取得
    public func openSubspace(at path: [String]) async throws -> Subspace? {
        try await connection.withTransaction { transaction in
            let layer = DirectoryLayer(database: self.connection.database)
            return try await layer.open(transaction: transaction, path: path)?.subspace
        }
    }

    /// ツリー構築
    public func buildTree(at path: [String] = [], maxDepth: Int = 2) async throws -> [DirectoryNode] {
        guard maxDepth > 0 else { return [] }

        let children = try await listChildren(at: path)
        var result: [DirectoryNode] = []

        for var child in children {
            if maxDepth > 1 {
                child.children = try await buildTree(at: child.path, maxDepth: maxDepth - 1)
            }
            result.append(child)
        }

        return result
    }
}
```

### 3. SubspaceExplorer

```swift
/// Subspace探索
public struct SubspaceExplorer: Sendable {
    private let connection: DatabaseConnection

    /// Subspace内の概要を取得
    public func inspect(subspace: Subspace) async throws -> SubspaceInfo {
        try await connection.withTransaction { transaction in
            // Items (R)
            let types = try await self.collectTypes(
                subspace.subspace(SubspaceKey.items),
                transaction
            )

            // Indexes (I)
            let indexes = try await self.collectIndexes(
                subspace.subspace(SubspaceKey.indexes),
                subspace.subspace(SubspaceKey.state),
                transaction
            )

            // Metadata (M)
            let metadata = try await self.collectMetadata(
                subspace.subspace(SubspaceKey.metadata),
                transaction
            )

            return SubspaceInfo(types: types, indexes: indexes, metadata: metadata)
        }
    }

    private func collectTypes(
        _ subspace: Subspace,
        _ transaction: any TransactionProtocol
    ) async throws -> [TypeInfo] {
        let (begin, end) = subspace.range()
        var typeCounts: [String: Int] = [:]

        for try await (key, _) in transaction.getRange(
            from: .firstGreaterOrEqual(begin),
            to: .firstGreaterOrEqual(end),
            snapshot: true
        ) {
            if let tuple = try? subspace.unpack(key),
               let typeName = tuple[0] as? String {
                typeCounts[typeName, default: 0] += 1
            }
        }

        return typeCounts.map { TypeInfo(name: $0.key, itemCount: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private func collectIndexes(
        _ indexSubspace: Subspace,
        _ stateSubspace: Subspace,
        _ transaction: any TransactionProtocol
    ) async throws -> [IndexInfo] {
        let (begin, end) = indexSubspace.range()
        var indexNames: Set<String> = []

        for try await (key, _) in transaction.getRange(
            from: .firstGreaterOrEqual(begin),
            to: .firstGreaterOrEqual(end),
            limit: 10000,
            snapshot: true
        ) {
            if let tuple = try? indexSubspace.unpack(key),
               let name = tuple[0] as? String {
                indexNames.insert(name)
            }
        }

        var indexes: [IndexInfo] = []
        for name in indexNames.sorted() {
            let stateKey = stateSubspace.pack(Tuple([name]))
            let state: IndexState
            if let data = try await transaction.getValue(for: stateKey, snapshot: true),
               let raw = data.first {
                state = IndexState(rawValue: raw) ?? .readable
            } else {
                state = .readable
            }

            indexes.append(IndexInfo(
                name: name,
                kind: IndexKindIdentifier.infer(from: name),
                state: state
            ))
        }

        return indexes
    }

    private func collectMetadata(
        _ subspace: Subspace,
        _ transaction: any TransactionProtocol
    ) async throws -> [String: String] {
        let (begin, end) = subspace.range()
        var metadata: [String: String] = [:]

        for try await (key, value) in transaction.getRange(
            from: .firstGreaterOrEqual(begin),
            to: .firstGreaterOrEqual(end),
            limit: 100,
            snapshot: true
        ) {
            if let tuple = try? subspace.unpack(key),
               let metaKey = tuple[0] as? String,
               let metaValue = String(data: Data(value), encoding: .utf8) {
                metadata[metaKey] = metaValue
            }
        }

        return metadata
    }
}
```

### 4. ItemExplorer

```swift
/// Item探索
public struct ItemExplorer: Sendable {
    private let connection: DatabaseConnection

    /// Item一覧を取得
    public func listItems(
        subspace: Subspace,
        typeName: String,
        limit: Int = 100,
        after: [UInt8]? = nil
    ) async throws -> ItemPage {
        try await connection.withTransaction { transaction in
            let typeSubspace = subspace.subspace(SubspaceKey.items).subspace(typeName)
            let (begin, end) = typeSubspace.range()
            let startKey = after ?? begin

            var items: [ItemInfo] = []
            var lastKey: [UInt8]?

            for try await (key, value) in transaction.getRange(
                from: .firstGreaterThan(startKey),
                to: .firstGreaterOrEqual(end),
                limit: limit + 1,
                snapshot: true
            ) {
                if items.count >= limit { break }

                if let tuple = try? typeSubspace.unpack(key) {
                    items.append(ItemInfo(
                        id: self.extractID(from: tuple),
                        typeName: typeName,
                        rawKey: key,
                        rawValue: value
                    ))
                    lastKey = key
                }
            }

            return ItemPage(
                items: items,
                nextCursor: items.count == limit ? lastKey : nil
            )
        }
    }

    /// 単一Item取得
    public func getItem(
        subspace: Subspace,
        typeName: String,
        id: String
    ) async throws -> ItemInfo? {
        try await connection.withTransaction { transaction in
            let typeSubspace = subspace.subspace(SubspaceKey.items).subspace(typeName)
            let key = typeSubspace.pack(Tuple([id]))

            guard let value = try await transaction.getValue(for: key, snapshot: true) else {
                return nil
            }

            return ItemInfo(id: id, typeName: typeName, rawKey: key, rawValue: value)
        }
    }

    private func extractID(from tuple: Tuple) -> String {
        var components: [String] = []
        for i in 0..<tuple.count {
            if let element = tuple[i] {
                components.append("\(element)")
            }
        }
        return components.joined(separator: ":")
    }
}
```

### 5. IndexInspector

```swift
/// インデックス解析
public struct IndexInspector: Sendable {
    private let connection: DatabaseConnection

    /// インデックス詳細を取得
    public func inspect(
        subspace: Subspace,
        indexName: String
    ) async throws -> IndexDetail {
        try await connection.withTransaction { transaction in
            let indexSubspace = subspace.subspace(SubspaceKey.indexes).subspace(indexName)
            let (begin, end) = indexSubspace.range()

            var entryCount = 0
            var sampleEntries: [IndexEntry] = []

            for try await (key, value) in transaction.getRange(
                from: .firstGreaterOrEqual(begin),
                to: .firstGreaterOrEqual(end),
                snapshot: true
            ) {
                entryCount += 1

                if sampleEntries.count < 10 {
                    if let tuple = try? indexSubspace.unpack(key) {
                        sampleEntries.append(IndexEntry(
                            keyComponents: self.extractComponents(from: tuple),
                            value: value
                        ))
                    }
                }
            }

            // 状態取得
            let stateSubspace = subspace.subspace(SubspaceKey.state)
            let stateKey = stateSubspace.pack(Tuple([indexName]))
            let state: IndexState
            if let data = try await transaction.getValue(for: stateKey, snapshot: true),
               let raw = data.first {
                state = IndexState(rawValue: raw) ?? .readable
            } else {
                state = .readable
            }

            let kind = IndexKindIdentifier.infer(from: indexName)

            return IndexDetail(
                name: indexName,
                kind: kind,
                state: state,
                entryCount: entryCount,
                sampleEntries: sampleEntries,
                subspaceStructure: kind.subspaceStructure
            )
        }
    }

    private func extractComponents(from tuple: Tuple) -> [String] {
        var components: [String] = []
        for i in 0..<tuple.count {
            components.append("\(tuple[i] ?? "nil")")
        }
        return components
    }
}
```

---

## モデル定義

### DirectoryNode

```swift
public struct DirectoryNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let path: [String]
    public var children: [DirectoryNode]

    public init(name: String, path: [String], children: [DirectoryNode] = []) {
        self.id = path.joined(separator: "/")
        self.name = name
        self.path = path
        self.children = children
    }
}
```

### SubspaceInfo

```swift
public struct SubspaceInfo: Sendable {
    public let types: [TypeInfo]
    public let indexes: [IndexInfo]
    public let metadata: [String: String]
}
```

### TypeInfo / IndexInfo

```swift
public struct TypeInfo: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let itemCount: Int
}

public struct IndexInfo: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let kind: IndexKindIdentifier
    public let state: IndexState
}
```

### IndexKindIdentifier

```swift
public enum IndexKindIdentifier: String, Sendable, CaseIterable {
    case scalar, count, sum, min, max, average
    case version, countUpdates, bitmap, rank
    case vector, fullText, spatial, graph
    case timeWindowLeaderboard

    public var subspaceStructure: SubspaceStructure {
        switch self {
        case .scalar, .min, .max, .countUpdates, .spatial:
            return .flat
        case .count, .sum, .average:
            return .aggregation
        case .version, .bitmap, .rank, .vector, .fullText, .graph, .timeWindowLeaderboard:
            return .hierarchical
        }
    }

    public var displayName: String { ... }
    public var symbolName: String { ... }

    public static func infer(from name: String) -> Self {
        let lower = name.lowercased()
        if lower.contains("vector") { return .vector }
        if lower.contains("fulltext") { return .fullText }
        // ... 他のパターン
        return .scalar
    }
}
```

### SubspaceStructure

```swift
public enum SubspaceStructure: String, Sendable {
    case flat           // [index]/[values]/[pk] = ''
    case hierarchical   // [index]/[layer]/[node] = data
    case aggregation    // [index]/[groupKey] = aggregatedValue
}
```

### IndexState

```swift
public enum IndexState: UInt8, Sendable {
    case readable = 0
    case writeOnly = 1
    case disabled = 2

    public var isUsable: Bool { self == .readable }
    public var displayName: String { ... }
}
```

### ItemInfo / ItemPage

```swift
public struct ItemInfo: Identifiable, Sendable {
    public let id: String
    public let typeName: String
    public let rawKey: [UInt8]
    public let rawValue: [UInt8]

    public var size: Int { rawValue.count }
    public func decodeJSON() -> [String: Any]? { ... }
}

public struct ItemPage: Sendable {
    public let items: [ItemInfo]
    public let nextCursor: [UInt8]?
    public var hasMore: Bool { nextCursor != nil }
}
```

### IndexDetail / IndexEntry

```swift
public struct IndexDetail: Sendable {
    public let name: String
    public let kind: IndexKindIdentifier
    public let state: IndexState
    public let entryCount: Int
    public let sampleEntries: [IndexEntry]
    public let subspaceStructure: SubspaceStructure
}

public struct IndexEntry: Sendable {
    public let keyComponents: [String]
    public let value: [UInt8]
    public var keyDescription: String { keyComponents.joined(separator: " → ") }
}
```

---

## UI層設計

### AppState

```swift
@MainActor
@Observable
public final class AppState {
    // Connection
    public var clusterFilePath = "/etc/foundationdb/fdb.cluster"
    public private(set) var isConnected = false

    // Explorers (non-observable)
    @ObservationIgnored private var connection: DatabaseConnection?
    @ObservationIgnored private var directoryExplorer: DirectoryExplorer?
    @ObservationIgnored private var subspaceExplorer: SubspaceExplorer?
    @ObservationIgnored private var itemExplorer: ItemExplorer?
    @ObservationIgnored private var indexInspector: IndexInspector?

    // Navigation
    public var selectedPath: [String]?
    public var selectedTypeName: String?
    public var selectedIndexName: String?

    // Data
    public private(set) var directoryTree: [DirectoryNode] = []
    public private(set) var currentSubspaceInfo: SubspaceInfo?
    public private(set) var currentIndexDetail: IndexDetail?
    public private(set) var currentItems: ItemPage?

    // Loading
    public private(set) var isLoading = false

    // Actions
    public func connect() async { ... }
    public func disconnect() { ... }
    public func selectDirectory(_ path: [String]) async { ... }
    public func selectType(_ name: String) async { ... }
    public func selectIndex(_ name: String) async { ... }
}
```

---

## 可視化階層

```
Level 1: Directory Tree      → FDBのディレクトリ階層
Level 2: Subspace Overview   → Types, Indexes, Metadata
Level 3: Type Detail         → Item一覧、フィールド構造
Level 4: Index Detail        → Kind, State, Subspace構造, サンプル
Level 5: Item Detail         → JSON表示、生データ
```

---

## 画面構成

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Database Studio                                              ⏤  ⬜  ✕  │
├─────────────────────────────────────────────────────────────────────────┤
│ 🟢 Connected: /etc/foundationdb/fdb.cluster                  [⚙️]      │
├───────────┬───────────────────────────────┬─────────────────────────────┤
│           │                               │                             │
│ Directory │  Subspace: app/users          │  Index: User_email          │
│           │                               │                             │
│ ▼ app     │  Types:                       │  Type: Scalar               │
│   users◀──│    📦 User (1,234)            │  State: ✅ readable         │
│   posts   │    📦 Profile (1,234)         │                             │
│   orders  │                               │  Structure: Flat            │
│ ▼ system  │  Indexes:                     │  [index]/[value]/[pk] = ''  │
│   meta    │    📊 User_email ✅           │                             │
│           │    🔢 User_count ✅           │  Entries: 1,234             │
│           │    ↗️ User_vec 🔨             │                             │
│           │    🔍 User_bio ✅             │  Sample:                    │
│           │                               │    alice@... → user_001     │
│           │                               │    bob@... → user_002       │
│           │                               │                             │
└───────────┴───────────────────────────────┴─────────────────────────────┘
```
