import SwiftUI
import Core

/// プレビュー用のモックデータ
@MainActor
enum StudioSampleData {

    // MARK: - Entity Tree

    static let entityTree: [EntityTreeNode] = [
        EntityTreeNode(
            name: "myapp",
            path: ["myapp"],
            children: [
                EntityTreeNode(
                    name: "users",
                    path: ["myapp", "users"],
                    children: [],
                    entities: []
                ),
                EntityTreeNode(
                    name: "products",
                    path: ["myapp", "products"],
                    children: [],
                    entities: []
                ),
                EntityTreeNode(
                    name: "documents",
                    path: ["myapp", "documents"],
                    children: [],
                    entities: []
                )
            ],
            entities: []
        ),
        EntityTreeNode(
            name: "analytics",
            path: ["analytics"],
            children: [],
            entities: []
        )
    ]

    // MARK: - Collection Statistics

    static let userCollectionStats = CollectionStats(
        typeName: "User",
        documentCount: 1250,
        storageSize: 1024 * 1024 * 2  // 2 MB
    )

    static let profileCollectionStats = CollectionStats(
        typeName: "Profile",
        documentCount: 1248,
        storageSize: 1024 * 512  // 512 KB
    )

    static let sessionCollectionStats = CollectionStats(
        typeName: "Session",
        documentCount: 3420,
        storageSize: 1024 * 1024  // 1 MB
    )

    /// 型名からコレクション統計を取得
    static func collectionStatistics(for typeName: String) -> CollectionStats? {
        switch typeName {
        case "User": return userCollectionStats
        case "Profile": return profileCollectionStats
        case "Session": return sessionCollectionStats
        default: return nil
        }
    }

    // MARK: - Items (User)

    /// ユーザーアイテム - ネストしたオブジェクト、boolean、null値を含む
    static let userRecords: [StudioRecord] = [
        makeRecord(
            id: "user_001",
            typeName: "User",
            fields: [
                "name": "Alice Johnson",
                "email": "alice@example.com",
                "age": 28,
                "isActive": true,
                "isAdmin": false,
                "address": [
                    "city": "Tokyo",
                    "country": "Japan",
                    "zipCode": "100-0001"
                ],
                "tags": ["developer", "swift", "ios"],
                "createdAt": "2024-01-15T09:30:00Z"
            ]
        ),
        makeRecord(
            id: "user_002",
            typeName: "User",
            fields: [
                "name": "Bob Smith",
                "email": "bob@example.com",
                "age": 32,
                "isActive": true,
                "isAdmin": true,
                "address": [
                    "city": "San Francisco",
                    "country": "USA",
                    "zipCode": "94102"
                ],
                "tags": ["manager", "product"],
                "createdAt": "2024-02-20T14:00:00Z"
            ]
        ),
        makeRecord(
            id: "user_003",
            typeName: "User",
            fields: [
                "name": "Carol Williams",
                "email": "carol@example.com",
                "age": 25,
                "isActive": false,
                "isAdmin": false,
                "address": [
                    "city": "London",
                    "country": "UK",
                    "zipCode": "SW1A 1AA"
                ],
                "tags": ["designer", "ui", "ux"],
                "createdAt": "2024-03-10T11:45:00Z",
                "deletedAt": "2024-12-01T00:00:00Z"
            ]
        ),
        makeRecord(
            id: "user_004",
            typeName: "User",
            fields: [
                "name": "Dave Brown",
                "email": "dave@example.com",
                "age": 41,
                "isActive": true,
                "isAdmin": false,
                "address": [
                    "city": "Berlin",
                    "country": "Germany",
                    "zipCode": "10115"
                ],
                "tags": ["data", "science", "python"],
                "createdAt": "2023-11-05T08:15:00Z"
            ]
        ),
        makeRecord(
            id: "user_005",
            typeName: "User",
            fields: [
                "name": "Eve Davis",
                "email": "eve@example.com",
                "age": 29,
                "isActive": true,
                "isAdmin": false,
                "address": [
                    "city": "Tokyo",
                    "country": "Japan",
                    "zipCode": "150-0002"
                ],
                "tags": ["security", "backend"],
                "createdAt": "2024-04-22T16:30:00Z"
            ]
        ),
        // null値テスト用
        makeRecord(
            id: "user_006",
            typeName: "User",
            fields: [
                "name": "Frank Miller",
                "email": "frank@example.com",
                "age": 35,
                "isActive": true,
                "isAdmin": false,
                // address なし (null)
                "tags": [],  // 空配列
                "createdAt": "2024-05-01T10:00:00Z"
            ]
        ),
        makeRecord(
            id: "user_007",
            typeName: "User",
            fields: [
                "name": "Grace Lee",
                "email": NSNull(),  // null メール
                "age": 27,
                "isActive": false,
                "isAdmin": false,
                "address": [
                    "city": "Seoul",
                    "country": "Korea",
                    "zipCode": "04523"
                ],
                "tags": ["intern"],
                "createdAt": "2024-06-15T12:00:00Z"
            ]
        )
    ]

    // MARK: - Items (Profile)

    static let profileRecords: [StudioRecord] = [
        makeRecord(
            id: "profile_001",
            typeName: "Profile",
            fields: [
                "userId": "user_001",
                "bio": "Software engineer passionate about mobile development",
                "avatar": "https://example.com/avatars/alice.jpg",
                "social": [
                    "twitter": "@alice_dev",
                    "github": "alicejohnson"
                ],
                "settings": [
                    "theme": "dark",
                    "notifications": true,
                    "language": "ja"
                ]
            ]
        ),
        makeRecord(
            id: "profile_002",
            typeName: "Profile",
            fields: [
                "userId": "user_002",
                "bio": "Product manager with 10 years of experience",
                "avatar": "https://example.com/avatars/bob.jpg",
                "social": [
                    "twitter": "@bob_pm",
                    "linkedin": "bobsmith"
                ],
                "settings": [
                    "theme": "light",
                    "notifications": true,
                    "language": "en"
                ]
            ]
        ),
        makeRecord(
            id: "profile_003",
            typeName: "Profile",
            fields: [
                "userId": "user_003",
                "bio": "UI/UX Designer creating beautiful experiences",
                "avatar": "https://example.com/avatars/carol.jpg",
                "social": [
                    "dribbble": "carol_design"
                ],
                "settings": [
                    "theme": "auto",
                    "notifications": false,
                    "language": "en"
                ]
            ]
        ),
        makeRecord(
            id: "profile_004",
            typeName: "Profile",
            fields: [
                "userId": "user_004",
                "bio": "Data scientist exploring ML and AI",
                "avatar": NSNull(),  // アバターなし
                "social": [:],  // 空のソーシャル
                "settings": [
                    "theme": "dark",
                    "notifications": true,
                    "language": "de"
                ]
            ]
        )
    ]

    // MARK: - Items (Session)

    static let sessionRecords: [StudioRecord] = [
        makeRecord(
            id: "session_001",
            typeName: "Session",
            fields: [
                "userId": "user_001",
                "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc123",
                "device": [
                    "type": "mobile",
                    "os": "iOS",
                    "version": "17.2"
                ],
                "ipAddress": "192.168.1.100",
                "isValid": true,
                "createdAt": "2025-01-10T08:00:00Z",
                "expiresAt": "2025-02-10T08:00:00Z"
            ]
        ),
        makeRecord(
            id: "session_002",
            typeName: "Session",
            fields: [
                "userId": "user_002",
                "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.def456",
                "device": [
                    "type": "desktop",
                    "os": "macOS",
                    "version": "14.2"
                ],
                "ipAddress": "10.0.0.50",
                "isValid": true,
                "createdAt": "2025-01-12T14:30:00Z",
                "expiresAt": "2025-02-12T14:30:00Z"
            ]
        ),
        makeRecord(
            id: "session_003",
            typeName: "Session",
            fields: [
                "userId": "user_001",
                "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ghi789",
                "device": [
                    "type": "tablet",
                    "os": "iPadOS",
                    "version": "17.2"
                ],
                "ipAddress": "192.168.1.101",
                "isValid": false,
                "createdAt": "2025-01-05T10:00:00Z",
                "expiresAt": "2025-01-15T10:00:00Z",
                "revokedAt": "2025-01-08T15:00:00Z"
            ]
        )
    ]

    // MARK: - Items (Document) - ベクトルデータを含む

    /// ベクトル埋め込みを生成（384次元のダミーデータ）
    private static func makeEmbedding(seed: Int) -> [Double] {
        (0..<384).map { i in
            let x = Double(seed + i) * 0.01
            return sin(x) * 0.5 + cos(x * 0.7) * 0.3
        }
    }

    static let documentRecords: [StudioRecord] = [
        makeRecord(
            id: "doc_001",
            typeName: "Document",
            fields: [
                "title": "Introduction to Machine Learning",
                "content": "Machine learning is a subset of artificial intelligence...",
                "author": "Alice Johnson",
                "category": "Technology",
                "tags": ["AI", "ML", "tutorial"],
                "embedding": makeEmbedding(seed: 1),
                "createdAt": "2024-06-15T10:00:00Z"
            ]
        ),
        makeRecord(
            id: "doc_002",
            typeName: "Document",
            fields: [
                "title": "Swift Concurrency Deep Dive",
                "content": "Swift concurrency introduces async/await patterns...",
                "author": "Bob Smith",
                "category": "Programming",
                "tags": ["Swift", "iOS", "concurrency"],
                "embedding": makeEmbedding(seed: 42),
                "createdAt": "2024-07-20T14:30:00Z"
            ]
        ),
        makeRecord(
            id: "doc_003",
            typeName: "Document",
            fields: [
                "title": "Database Design Patterns",
                "content": "Effective database design is crucial for scalability...",
                "author": "Carol Williams",
                "category": "Database",
                "tags": ["database", "design", "patterns"],
                "embedding": makeEmbedding(seed: 123),
                "createdAt": "2024-08-05T09:15:00Z"
            ]
        )
    ]

    // MARK: - Record Construction

    /// Creates a preview record and measures its JSON representation.
    private static func makeRecord(id: String, typeName: String, fields: [String: Any]) -> StudioRecord {
        let encodedFields: Data
        do {
            encodedFields = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        } catch {
            encodedFields = Data()
        }
        return StudioRecord(
            id: id,
            typeName: typeName,
            fields: fields,
            jsonByteCount: encodedFields.count
        )
    }

    /// Returns preview records for an entity type.
    static func records(for typeName: String) -> [StudioRecord] {
        switch typeName {
        case "User": return userRecords
        case "Profile": return profileRecords
        case "Session": return sessionRecords
        case "Document": return documentRecords
        default: return []
        }
    }
}
