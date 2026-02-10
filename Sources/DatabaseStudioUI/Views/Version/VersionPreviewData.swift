import Foundation

/// Version Preview 用サンプルデータ
enum VersionPreviewData {

    static let document: VersionDocument = VersionDocument(
        recordID: "user-042",
        entityName: "User",
        versions: versions,
        fieldNames: ["id", "name", "email", "status", "role", "loginCount"]
    )

    static let versions: [VersionEntry] = [
        VersionEntry(
            version: 5,
            timestamp: Date(),
            snapshot: [
                "id": "user-042",
                "name": "Alice Smith",
                "email": "alice.smith@example.com",
                "status": "premium",
                "role": "admin",
                "loginCount": "142"
            ],
            author: "system"
        ),
        VersionEntry(
            version: 4,
            timestamp: Date().addingTimeInterval(-7200),
            snapshot: [
                "id": "user-042",
                "name": "Alice Smith",
                "email": "alice@example.com",
                "status": "active",
                "role": "admin",
                "loginCount": "138"
            ],
            author: "alice"
        ),
        VersionEntry(
            version: 3,
            timestamp: Date().addingTimeInterval(-86400),
            snapshot: [
                "id": "user-042",
                "name": "Alice",
                "email": "alice@example.com",
                "status": "active",
                "role": "user",
                "loginCount": "95"
            ],
            author: "admin"
        ),
        VersionEntry(
            version: 2,
            timestamp: Date().addingTimeInterval(-259200),
            snapshot: [
                "id": "user-042",
                "name": "Alice",
                "email": "alice@example.com",
                "status": "pending",
                "role": "user",
                "loginCount": "12"
            ],
            author: "system"
        ),
        VersionEntry(
            version: 1,
            timestamp: Date().addingTimeInterval(-604800),
            snapshot: [
                "id": "user-042",
                "name": "Alice",
                "email": "alice@example.com",
                "status": "pending",
                "role": "user"
            ],
            author: "system"
        ),
    ]
}
