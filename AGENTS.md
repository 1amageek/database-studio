# Database Studio

FoundationDBのデータを閲覧するためのmacOS GUIアプリケーション。

**仕様:** [CONTEXT.md](/CONTEXT.md) を参照

## プロジェクト構成

```
Sources/
├── DatabaseStudioCore/    # ロジック層（プラットフォーム非依存）
├── DatabaseStudioUI/      # UI層（SwiftUI・macOS専用）
└── DatabaseStudio/        # アプリケーションエントリポイント
```

## 依存関係

- database-framework: FDB操作
- database-kit: 型定義（Persistable等）
- fdb-swift-bindings: FoundationDB Swift bindings

---

## FoundationDB 基礎知識

### 接続方法

FoundationDB への接続にはクラスタファイルが必要。

**クラスタファイル形式:**
```
description:ID@IP:PORT,IP:PORT,...
```

**デフォルトパス:** `/etc/foundationdb/fdb.cluster`

**接続手順:**
1. API バージョンを指定
2. クラスタファイルパスでデータベースを開く

```swift
// fdb-swift-bindings での接続例
import FoundationDB

// API バージョン設定
try FDB.selectAPIVersion(730)

// データベースを開く
let fdb = FDB()
let database = try fdb.open(clusterFile: "/etc/foundationdb/fdb.cluster")
```

### トランザクション

FoundationDB は ACID トランザクションを提供。楽観的並行制御（optimistic concurrency control）を使用。

- **短命設計**: トランザクションは通常5秒未満で完了すべき
- **コンフリクト検出**: コミット時にコンフリクトを検出、失敗時はクライアントがリトライ
- **スナップショット読み取り**: 読み取りはデータベースの瞬間的なスナップショットから取得

```swift
// トランザクションの基本パターン
try await database.withTransaction { tx in
    // 読み取り
    let value = try await tx.get(key: keyBytes)

    // 書き込み
    tx.set(key: keyBytes, value: valueBytes)

    // 削除
    tx.clear(key: keyBytes)

    // 範囲読み取り
    for try await (key, value) in tx.getRange(from: begin, to: end) {
        // ...
    }
}
```

### キー・バリュー操作

| 操作 | 説明 |
|------|------|
| `get(key)` | キーに対応する値を取得 |
| `set(key, value)` | キーと値を設定（上書き） |
| `clear(key)` | キーと値を削除 |
| `getRange(begin, end)` | 範囲内のキー・バリューペアを取得 (`begin <= k < end`) |
| `clearRange(begin, end)` | 範囲内のキーをすべて削除 |

### Directory Layer

Directory Layer は階層的な名前空間を管理する仕組み。Unix ファイルシステムのようなパス構造を提供。

**特徴:**
- パスを短いプレフィックスにマッピング（キーを短く保つ）
- ディレクトリの移動（リネーム）が高速
- 論理的には階層構造だが、物理的なプレフィックスはネストしない

**主要操作:**
- `createOrOpen(path:)`: 作成または既存を開く
- `open(path:)`: 既存を開く（存在しなければエラー）
- `create(path:)`: 新規作成（存在すればエラー）
- `list(path:)`: 子ディレクトリ一覧
- `move(oldPath:newPath:)`: 移動
- `remove(path:)`: 削除

## コーディング規約

- Swift 6.2、Strict Concurrency
- @Observable for ViewModels
- NavigationSplitView for 3ペイン構成
- すべてのDB操作は async/await

---

## ビルド方法

### コマンドライン

```bash
swift build
swift run
```

### Xcode

Xcode で開く場合は、GUI アプリ用の環境変数設定が必要：

```bash
# 方法1: スクリプトを使用（推奨）
./open-xcode.sh

# 方法2: 手動で環境変数を設定
launchctl setenv PKG_CONFIG_PATH "/usr/local/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"
launchctl setenv PATH "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
open -a Xcode .
```

**注意:**
- 通常の `open -a Xcode .` では `CFoundationDB` モジュールが見つからないエラーが発生する
- Xcode が既に起動中の場合は再起動が必要
- `launchctl setenv` は GUI アプリがアクセスする環境変数を設定する

---

## DirectoryLayer API リファレンス

fdb-swift-bindings の DirectoryLayer は FoundationDB の階層的ディレクトリ管理を提供する。

### 重要: DirectoryLayer は database を必要とする

```swift
// ✅ 正しい使い方
let directoryLayer = DirectoryLayer(database: database)

// ❌ 間違い - コンパイルエラー
let directoryLayer = DirectoryLayer()  // database引数が必須
```

### 初期化

```swift
import FoundationDB

// 標準的な初期化（推奨）
let directoryLayer = DirectoryLayer(database: database)

// カスタムSubspaceを使用
let customLayer = DirectoryLayer(
    database: database,
    nodeSubspace: Subspace(prefix: [0x01, 0xFE]),
    contentSubspace: Subspace(prefix: [0x01])
)

// DatabaseProtocol拡張を使用
let layer = database.makeDirectoryLayer()
```

### 主要メソッド

すべてのメソッドは **async throws** で、**トランザクションを内部で管理する**。
外部でトランザクションを渡す必要はない。

#### ディレクトリ作成・オープン

```swift
// 作成または既存を開く（推奨）
let dir = try await directoryLayer.createOrOpen(path: ["app", "users"])

// 新規作成のみ（存在すればエラー）
let newDir = try await directoryLayer.create(path: ["app", "logs"])

// 既存を開くのみ（存在しなければエラー）
let existingDir = try await directoryLayer.open(path: ["app", "users"])
```

#### ディレクトリ操作

```swift
// 子ディレクトリ一覧
let children = try await directoryLayer.list(path: ["app"])
// → ["users", "logs", "settings"]

// ルートの子一覧
let rootChildren = try await directoryLayer.list()

// 存在確認
let exists = try await directoryLayer.exists(path: ["app", "users"])

// 移動
let movedDir = try await directoryLayer.move(
    oldPath: ["app", "old-name"],
    newPath: ["app", "new-name"]
)

// 削除（子孫も含めて削除）
try await directoryLayer.remove(path: ["app", "temp"])
```

### DirectorySubspace

`DirectoryLayer` のメソッドは `DirectorySubspace` を返す。

```swift
let userDir = try await directoryLayer.createOrOpen(path: ["app", "users"])

// プロパティ
userDir.path       // ["app", "users"]
userDir.prefix     // [UInt8] - HCAが割り当てたプレフィックス
userDir.subspace   // Subspace インスタンス
userDir.type       // DirectoryType? (.partition or .custom("..."))
userDir.isPartition // Bool

// データ操作に使用
let key = userDir.subspace.pack(Tuple(["user123"]))
let (begin, end) = userDir.subspace.range()
```

### DirectoryType

```swift
// パーティション（独立した名前空間）
let partition = try await directoryLayer.createOrOpen(
    path: ["isolated"],
    type: .partition
)

// カスタムタイプ
let custom = try await directoryLayer.createOrOpen(
    path: ["special"],
    type: .custom("my-layer")
)
```

### DirectoryError

```swift
do {
    let dir = try await directoryLayer.open(path: ["nonexistent"])
} catch DirectoryError.directoryNotFound(let path) {
    print("Not found: \(path)")
} catch DirectoryError.directoryAlreadyExists(let path) {
    print("Already exists: \(path)")
} catch DirectoryError.layerMismatch(let expected, let actual) {
    print("Layer mismatch")
} catch DirectoryError.cannotMoveAcrossPartitions(let from, let to) {
    print("Cannot move across partitions")
}
```

### 使用パターン

#### パターン1: DirectoryLayerのみ使用（推奨）

DirectoryLayerはトランザクションを内部管理するため、外部トランザクションは不要。

```swift
public struct DirectoryBrowser: Sendable {
    nonisolated(unsafe) private let database: any DatabaseProtocol

    public func listChildren(at path: [String]) async throws -> [String] {
        let directoryLayer = DirectoryLayer(database: database)
        return try await directoryLayer.list(path: path)
    }

    public func openSubspace(at path: [String]) async throws -> Subspace? {
        let directoryLayer = DirectoryLayer(database: database)
        do {
            let dir = try await directoryLayer.open(path: path)
            return dir.subspace
        } catch DirectoryError.directoryNotFound {
            return nil
        }
    }
}
```

#### パターン2: DirectoryLayer + 追加トランザクション

ディレクトリを開いた後、そのSubspaceでデータを読み書きする場合。

```swift
public struct SchemaInspector: Sendable {
    nonisolated(unsafe) private let database: any DatabaseProtocol

    public func inspect(at path: [String]) async throws -> SchemaInfo? {
        // Step 1: DirectoryLayerでディレクトリを開く（内部トランザクション）
        let directoryLayer = DirectoryLayer(database: database)
        let directory: DirectorySubspace
        do {
            directory = try await directoryLayer.open(path: path)
        } catch DirectoryError.directoryNotFound {
            return nil
        }

        // Step 2: 取得したSubspaceでデータを読む（別トランザクション）
        return try await database.withTransaction(configuration: .default) { tx in
            let subspace = directory.subspace
            let (begin, end) = subspace.range()

            var items: [String] = []
            for try await (key, _) in tx.getRange(
                from: .firstGreaterOrEqual(begin),
                to: .firstGreaterOrEqual(end),
                snapshot: true
            ) {
                if let tuple = try? subspace.unpack(key),
                   let name = tuple[0] as? String {
                    items.append(name)
                }
            }
            return SchemaInfo(items: items)
        }
    }
}
```

### nonisolated(unsafe) の必要性

`DatabaseProtocol` は `Sendable` だが、`actor` 内で保持する場合は `nonisolated(unsafe)` が必要。

```swift
// ✅ 正しい: struct + nonisolated(unsafe)
public struct DirectoryBrowser: Sendable {
    nonisolated(unsafe) private let database: any DatabaseProtocol
    // ...
}

// ❌ 間違い: actor + 通常のプロパティ
public actor DirectoryBrowser {
    private let database: any DatabaseProtocol  // Sendable エラー
    // ...
}
```

### よくある間違い

#### 1. database引数の欠落

```swift
// ❌ コンパイルエラー
let layer = DirectoryLayer()

// ✅ 正しい
let layer = DirectoryLayer(database: database)
```

#### 2. transactionを渡そうとする

```swift
// ❌ 間違い - publicメソッドはtransactionを取らない
let names = try await layer.list(transaction: tx, path: ["app"])

// ✅ 正しい - トランザクションは内部管理
let names = try await layer.list(path: ["app"])
```

#### 3. 古いAPI（transaction引数あり）の使用

fdb-swift-bindings の現在のバージョンでは、すべてのpublicメソッドがトランザクションを内部管理する。
以前の `transaction:` 引数を持つAPIは廃止された。

---

## SubspaceKey 定数

database-framework が定義するSubspace構造:

```swift
// DatabaseEngine/Types/SubspaceKey.swift
public enum SubspaceKey {
    public static let items = "R"      // Item (Persistable) データ
    public static let indexes = "I"    // Index エントリ
    public static let state = "T"      // Index 状態
    public static let metadata = "M"   // メタデータ
    public static let blobs = "B"      // Blob チャンク
}
```

使用例:

```swift
let directory = try await directoryLayer.open(path: ["app", "users"])
let subspace = directory.subspace

// Items subspace: [prefix]/R/[typeName]/[id]
let itemsSubspace = subspace.subspace(SubspaceKey.items)
let userItems = itemsSubspace.subspace("User")

// Indexes subspace: [prefix]/I/[indexName]/[values]/[id]
let indexesSubspace = subspace.subspace(SubspaceKey.indexes)

// State subspace: [prefix]/T/[indexName]
let stateSubspace = subspace.subspace(SubspaceKey.state)
```

---

## Schema.Ontology — オントロジーの型消去パターン

**詳細設計**: `database-framework/Docs/OWL-DL-Design.md` セクション 8 を参照

### 概要

オントロジーは `Schema.Ontology`（Core モジュール）として型消去され、
Entity と同様にシステム全体を自動的に流れる。

```
OWLOntology (Graph)
    ↓ .asSchemaOntology()
Schema.Ontology (Core) ← Codable, 型消去
    ↓ Schema(types, ontology:)
FDBContainer.init
    ↓ SchemaRegistry.persist()
FDB: _schema_ontology → JSON
    ↓ SchemaResponse
Client ← ontology 自動転送
```

### 型の役割

| 型 | モジュール | 役割 |
|---|---------|------|
| `OWLOntology` | Graph (database-kit) | 構築（DSL）、推論、検証 |
| `Schema.Ontology` | Core (database-kit) | 永続化、転送、モジュール境界の型消去 |

### Schema.Ontology 構造

```swift
extension Schema {
    public struct Ontology: Sendable, Codable, Hashable {
        public let iri: String              // オントロジー IRI
        public let typeIdentifier: String   // 具象型識別子（例: "OWLOntology"）
        public let encodedData: Data        // JSON エンコード済みデータ
    }
}
```

### AnyIndexDescriptor との類似性

| 観点 | AnyIndexDescriptor | Schema.Ontology |
|------|-------------------|-----------------|
| 配置 | Core | Core |
| 具象型 | IndexDescriptor | OWLOntology (Graph) |
| 永続化 | `_schema/[name]` | `_schema_ontology` |
| 転送 | SchemaResponse.entities[].indexes | SchemaResponse.ontology |

### FDB キーレイアウト

```
(_schema, "EntityName")  → JSON(Schema.Entity)     ← Entity 永続化
(_schema_ontology)       → JSON(Schema.Ontology)    ← Ontology 永続化
```

### 変換

```swift
// Graph モジュール側
let owlOntology = OntologyPolicy.buildBaseOntology()
let schemaOntology = owlOntology.asSchemaOntology()  // OWLOntology → Schema.Ontology

// GraphIndex モジュール側（復元）
let restored = try OWLOntology(schemaOntology: schemaOntology)  // Schema.Ontology → OWLOntology
```

---

## SwiftUI Inspector ルール

macOS/iPadOS でコンテキスト依存の補足情報を表示するトレーリングサイドバー。

### Inspector とは

- **macOS/iPadOS**: 右側のトレーリングサイドバーとして表示
- **iPhone**: シートとして表示
- **NavigationSplitView の detail ペインとは別物**

### 配置ルール

**Inspector は必ず detail ペインの View に直接アタッチする。**

```swift
// ✅ 正しい配置
NavigationSplitView {
    // Sidebar
} content: {
    // Content
} detail: {
    DetailView()
        .inspector(isPresented: $showInspector) {
            InspectorContent()
        }
}

// ❌ 間違い - NavigationSplitView の外
NavigationSplitView {
    // ...
} detail: {
    DetailView()
}
.inspector(isPresented: $showInspector) {  // ← 間違った位置
    InspectorContent()
}
```

### 基本的な実装

```swift
struct MainView: View {
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ContentView()
        } detail: {
            DetailView()
                .inspector(isPresented: $showInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
                }
        }
        .toolbar {
            Button {
                showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
        }
    }
}
```

### キーボードショートカット

`InspectorCommands` を使用して標準のキーボードショートカットを有効化:

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .commands {
            InspectorCommands()
        }
    }
}
```

### Inspector の用途

- 選択したアイテムのメタデータ表示
- 関連情報（Indexes、Properties等）の表示
- フォーマット設定パネル（Keynote スタイル）
- アクションライブラリ（Shortcuts スタイル）

### 参考資料

- [Apple WWDC23: Inspectors in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10161/)
- [Create with Swift: Presenting an Inspector](https://www.createwithswift.com/presenting-an-inspector-with-swiftui/)
