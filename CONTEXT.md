# Database Studio 設計仕様

## 目的

Database Studio は、`database-framework` で構築されたデータベースの
スキーマ、索引、オントロジー、グラフ、およびレコード操作を検査する
macOS アプリケーションです。

## 実行境界

```text
User interaction
      |
DatabaseStudioState
      |
      +-- StudioDatabaseSession
      |       |
      |       +-- SQLiteStorageEngine / FDBStorageEngine
      |       +-- DatabaseFormatCatalog validation
      |       +-- SchemaRegistry / OntologyStore
      |
      +-- Authenticated DatabaseWire runtime
              |
              +-- query / mutation / graph / ontology / job operations
```

`StorageEngine` への直接接続は、canonical database format の検証と
schema/ontology inspection に限定します。record CRUD、query、statistics は
アプリケーション固有 runtime の意味論を必要とするため、直接 storage API
として再実装しません。

現在 DatabaseWire runtime が未設定の状態では、record operation は
`StudioError.databaseRuntimeRequired` を返します。空配列、疑似レコード、成功値
への fallback は行わず、UI がエラーを表示します。

## 状態所有

| 型 | 責務 |
|---|---|
| `DatabaseStudioState` | 接続、選択、record operation、UI session state |
| `StudioDatabaseSession` | storage lifecycle、catalog validation、schema/ontology access |
| `MetricsDashboardState` | monitoring lifecycle と dashboard state |
| `DatabaseMetricsRecorder` | operation outcome、latency、slow-query history |
| `ConnectionHistoryStore` | 保存済み database connection history |
| `QueryHistoryStore` | 保存済み query history |

## データフロー

### 接続と schema inspection

```text
file path
  -> DatabaseStorageKind detection
  -> StorageEngine creation
  -> DatabaseFormatCatalog validation
  -> SchemaRegistry.loadAll()
  -> entity navigation tree
```

catalog validation に失敗した接続は `.connected` のまま残しません。engine を
shutdown して session state を破棄し、接続エラーとして扱います。

### record operation

```text
UI intent
  -> DatabaseStudioState
  -> StudioDatabaseSession
  -> authenticated DatabaseWire runtime required
  -> typed result or typed failure
```

DatabaseWire runtime が構成されるまでは、最後の境界で決定的に失敗します。

### import

```text
selected file
  -> background Data read
  -> MainActor parse and ParsedRecordImport ownership
  -> Array/Dictionary copy-on-write views
  -> record mutation operation
```

import preview と確定処理の間で JSON serialization round-trip を挟みません。
ID 変換が必要な確定時だけ collection を copy-on-write で変更します。

### export

```text
StudioRecord collection
  -> selected encoder
  -> owned Data output
  -> selected file destination
```

JSONL と CSV は全行の中間配列を作らず output buffer へ逐次追加します。
serialize/write failure は `RecordExportError` として UI へ返し、record skip、
空 `Data`、`Bool` への失敗丸めは行いません。

## 不変条件

- database semantics を Studio の direct-storage layer に複製しない。
- canonical database format を持たない storage を接続成功にしない。
- 未構成の record runtime を空結果や成功として扱わない。
- import/export の変換失敗を無視しない。
- large payload path では、所有 buffer と COW view を維持して不要な
  re-materialization を避ける。
- declaration は実装言語、calling convention、ABI、memory layout ではなく、
  domain responsibility、behavior、state、ownership、lifecycle で命名する。

## 検証

- app build: Xcode project の `Database Studio` scheme
- app tests: `Database StudioTests`
- package tests: `GraphDocumentTests` と `DatabaseStudioStateTests`
- invalid catalog、disconnected operation、RDF literal validation、import/export
  failure を成功ケースと分離して検証する。
