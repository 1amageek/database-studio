# Database Studio - 仕様書

## 概要

FoundationDB + database-framework で構築されたデータストアを閲覧するための macOS アプリケーション。

**目的:** 開発者がデータの確認・デバッグを行う

**対象ユーザー:** database-framework を使用する開発者

---

## ユースケース

### UC1: データのデバッグ（最重要）

「アプリでデータが正しく表示されない。DBに何が保存されているか確認したい」

**フロー:**
1. FDB に接続
2. ディレクトリを探す
3. Type を選択
4. Items から該当データを探す
5. JSON の中身を確認

### UC2: データ保存の確認

「コードを書いた。データがちゃんと保存されたか確認したい」

**フロー:**
1. Type を開く
2. 新しい Item を探す
3. 値を確認

### UC3: スキーマの把握

「このデータストアにどんな Type があるか知りたい」

**フロー:**
1. ディレクトリツリーを展開
2. Types を確認

### UC4: Index の確認（低頻度）

「Index が正しく設定されているか確認したい」

**フロー:**
1. ディレクトリを選択
2. Index 一覧を確認

---

## 機能要件

### 必須機能

| 機能 | 説明 |
|------|------|
| FDB 接続 | クラスタファイルを指定して接続 |
| ディレクトリ階層表示 | ツリー形式でディレクトリを表示 |
| Type 一覧表示 | 各ディレクトリの Types を表示（アイテム数付き） |
| Items 一覧表示 | 選択した Type の Items をテーブル表示 |
| Item 詳細表示 | 選択した Item の JSON を表示 |

### 重要機能

| 機能 | 説明 |
|------|------|
| JSON コピー | デバッグ用にクリップボードにコピー |
| Items ソート | ID順、新しい順など |

### オプション機能

| 機能 | 説明 |
|------|------|
| Items 検索/フィルタ | ID や値で検索 |
| Index 一覧表示 | 定義されている Index を表示 |
| Index 詳細表示 | Index のエントリを表示 |

---

## 画面構成

### 3ペイン構成（推奨）

```
┌─────────────┬───────────────────┬───────────────────┐
│  Sidebar    │     Content       │      Detail       │
│             │                   │                   │
│ Directory   │   Items Table     │   Item Detail     │
│ + Types     │                   │   (JSON)          │
│             │                   │                   │
└─────────────┴───────────────────┴───────────────────┘
```

### 画面一覧

| 画面 | 役割 | 表示内容 |
|------|------|----------|
| Sidebar | ナビゲーション | ディレクトリ階層 + Types |
| Content | データ一覧 | Items テーブル（ID, プレビュー, サイズ） |
| Detail | データ詳細 | Item の JSON 表示 |
| Inspector | メタ情報（オプション） | Index 一覧、Type 情報 |

### 状態遷移

```
[未接続] → 接続設定 → [接続済み]
                          ↓
                    ディレクトリ選択
                          ↓
                      Type 選択
                          ↓
                     Items 読み込み
                          ↓
                      Item 選択
                          ↓
                     詳細表示
```

---

## データモデル

### DirectoryNode

```swift
struct DirectoryNode {
    let name: String           // ディレクトリ名
    let path: [String]         // フルパス
    var children: [DirectoryNode]  // 子ディレクトリ
    var types: [TypeInfo]      // このディレクトリの Types
    let isLeaf: Bool           // 子を持たないか
}
```

### TypeInfo

```swift
struct TypeInfo {
    let name: String           // 型名（例: "User"）
    let itemCount: Int         // アイテム数
}
```

### ItemInfo

```swift
struct ItemInfo {
    let id: String             // アイテムID
    let typeName: String       // 型名
    let rawKey: [UInt8]        // FDB キー
    let rawValue: [UInt8]      // FDB 値
    let size: Int              // 値のサイズ
}
```

### TreeSelection

```swift
enum TreeSelection {
    case directory([String])           // ディレクトリパス
    case type([String], String)        // ディレクトリパス + 型名
}
```

---

## 設計方針

### シンプルさを優先

- 核となる機能に集中する
- 使用頻度の低い機能（Index詳細など）は後回し
- 4カラムより3カラムを優先

### 一方向のデータフロー

```
User Action → ViewModel → Model → View Update
```

### 非同期処理

- すべての DB 操作は async/await
- ローディング状態を明示的に管理
