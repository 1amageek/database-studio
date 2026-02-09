# Database Studio

FoundationDB の データブラウザ & グラフビジュアライザ。macOS ネイティブアプリ。

[database-framework](https://github.com/1amageek/database-framework) の `SchemaRegistry` を通じて、`@Persistable` 型のデータを GUI で閲覧・操作できる。

## 機能

### データブラウザ

- **接続管理** — クラスタファイル指定で FoundationDB に接続
- **エンティティツリー** — `Schema.Entity` をディレクトリ階層で表示
- **アイテムテーブル** — 選択エンティティのレコードをページング付きテーブル表示
- **CRUD** — アイテムの作成・編集・削除
- **クエリビルダー** — GUI で述語を構築してフィルタリング
- **インポート / エクスポート** — CSV・JSON 対応
- **スキーマ可視化** — フィールド定義・インデックス・ディレクトリ構造の確認
- **パフォーマンスメトリクス** — 操作時間の記録・スロークエリログ

### グラフビジュアライザ

RDF トリプル・OWL オントロジー・GraphIndex データをフォースレイアウトで可視化する。

- **Force-Directed Layout** — Barnes-Hut O(N log N) 反発力 + Spring 引力
- **LOD レンダリング** — ズームレベルに応じた 4 段階の描画詳細度
- **ビューポートカリング** — 画面外のノード・エッジを描画スキップ
- **N-hop 近傍フィルタ** — 選択ノードから N ホップ以内のノードのみ表示
- **エッジラベルフィルタ** — 表示するリレーション種別を選択
- **ノード検索** — ラベルによるノード検索・ハイライト
- **ビジュアルマッピング** — ノードサイズ・カラーを PageRank・コミュニティ等にマッピング
- **SPARQL コンソール** — クエリパネル（FoundationDB 接続時に実行可能）
- **ミニマップ** — グラフ全体のオーバーレイ表示
- **Inspector** — 選択ノードの IRI・メタデータ・接続エッジ・メトリクスを表示

## 要件

- macOS 15+
- Swift 6
- FoundationDB（ローカルにインストール済み）

## ビルド

```bash
swift build
```

Xcode で開く場合:

```bash
open Studio.xcworkspace
```

## 依存関係

| パッケージ | 用途 |
|-----------|------|
| [database-framework](https://github.com/1amageek/database-framework) | DatabaseEngine, SchemaRegistry, CatalogDataAccess |
| [database-kit](https://github.com/1amageek/database-kit) | Persistable, Schema.Entity, Graph (OWL/RDF) |

## アーキテクチャ

```
DatabaseStudioUI (SwiftUI)
├── Views/          ← UI コンポーネント
├── ViewModels/     ← @Observable 状態管理
├── Services/       ← StudioDataService, MetricsService
└── Query/          ← クエリビルダー・履歴

         ↓ async/await

database-framework
├── SchemaRegistry  ← Schema.Entity の永続化・読み取り
├── CatalogDataAccess ← 動的データアクセス（@Persistable 型不要）
└── DatabaseEngine  ← FDBContainer, FDBContext
```

## ライセンス

MIT
