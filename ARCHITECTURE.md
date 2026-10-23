# Database Studio Architecture

Database Studio は、database-framework を利用するデータベースの schema、
ontology、query 結果を可視化する macOS UI である。データベース意味論や物理
index layout を再実装しない。

## 責務境界

```text
DatabaseKit
  Schema / IndexDescriptor / IndexDefinition / IndexType
        |
        v
DatabaseEngine
  SchemaRegistry / runtime and administration contracts
        |
        v
DatabaseStudioUI
  session state / presentation models / SwiftUI views
```

| 層 | 所有するもの | Studio が行うこと |
|---|---|---|
| DatabaseKit | schema と論理 index 定義 | 型付き定義をそのまま表示する |
| database-framework | 実行、lifecycle、物理配置 | 公開された管理契約だけを消費する |
| storage-kit | storage transaction と backend | 接続済み engine 経由で catalog を読む |
| DatabaseStudioUI | UI state と presentation | 表示用 label、icon、画面遷移を提供する |

Studio は index 名から種類を推測せず、独自の index type enum や物理 subspace
model を持たない。

## パッケージ構成

現在の product は `DatabaseStudioUI` だけである。

```text
DatabaseStudioUI
├── ApplicationState   connection and screen state
├── Services           storage session and metrics
├── Models             Studio-owned presentation values
├── Query              query construction and history
├── Components         reusable SwiftUI components
└── Views              schema, index, items, graph, map, search, vector, ...
```

`StudioDatabaseSession` が storage engine と `SchemaRegistry` の lifetime を所有する。
接続解除時には engine の shutdown を要求して完了を待ち、registry と読み込んだ
entity を破棄する。

## 接続と capability

```text
file path
  -> DatabaseStorageKind
      -> SQLiteStorageEngine or FDBStorageEngine
          -> connectivity / format validation
              -> SchemaRegistry.loadAll()
                  -> [Schema.Entity]
```

直接 storage に接続した session が提供するのは catalog と ontology の inspection
である。認証済み application runtime を必要とする record read/write、statistics
などは成功値へ丸めず、`StudioError.databaseRuntimeRequired` で失敗する。

## Index presentation

Studio の index 表示は `IndexDescriptor` を唯一の論理情報源とする。

```text
Schema.Entity.indexDescriptors
  -> IndexDescriptor
      -> IndexIdentity                  stable UI identity
      -> IndexType                      label and symbol
      -> IndexDefinition<FieldIdentity> complete configuration
      -> [IndexKey<FieldIdentity>]      ordered keys
      -> includedFieldNames             covering projection
```

`SchemaDisplayMetadata.swift` は DatabaseKit の型を UI 向けに表示する純粋な変換だけ
を所有する。`IndexDetailView` と `CompactIndexRow` は、その変換結果を表示する。

### 不変条件

- index 名は schema に保存された明示名を表示する。
- 種類は `IndexType` から取得し、名前や field 数から推測しない。
- 完全な設定は `IndexDefinition` の associated values から取得する。
- key 順序は `IndexKey.order` を保持する。
- covering field と key field を混同しない。
- lifecycle や statistics は framework の管理 API から得た場合だけ表示する。
- 物理 key prefix や generation fingerprint を UI 側で組み立てない。

## 状態と並行性

UI session と画面状態は `@MainActor` が所有する。storage transaction は engine の
transaction API を通し、UI state を transaction closure に共有しない。長時間の
処理は cancellation を伝播し、失敗を空結果や既定状態へ変換しない。

## 依存方向

```text
DatabaseStudioUI
  -> DatabaseEngine
  -> DatabaseKit
  -> StorageKit and selected backend products

DatabaseKit      -X-> DatabaseStudioUI
DatabaseEngine   -X-> DatabaseStudioUI
StorageKit       -X-> DatabaseStudioUI
```

Studio 固有の表示都合を core package へ逆流させない。新しい index family が追加
された場合は DatabaseKit の `IndexType` / `IndexDefinition` を先に拡張し、Studio は
その公開契約の表示だけを追加する。
