import Foundation

/// Analytics Preview 用サンプルデータ
@MainActor
enum AnalyticsPreviewData {

    static let document: AnalyticsDocument = AnalyticsDocument(
        items: items,
        entityName: "Order"
    )

    nonisolated(unsafe) static let items: [[String: Any]] = [
        ["id": "ord-001", "status": "completed", "category": "Electronics", "amount": 1200.0, "quantity": 2],
        ["id": "ord-002", "status": "pending", "category": "Books", "amount": 45.0, "quantity": 3],
        ["id": "ord-003", "status": "completed", "category": "Electronics", "amount": 890.0, "quantity": 1],
        ["id": "ord-004", "status": "cancelled", "category": "Clothing", "amount": 120.0, "quantity": 2],
        ["id": "ord-005", "status": "completed", "category": "Books", "amount": 32.0, "quantity": 1],
        ["id": "ord-006", "status": "pending", "category": "Electronics", "amount": 2400.0, "quantity": 1],
        ["id": "ord-007", "status": "completed", "category": "Clothing", "amount": 85.0, "quantity": 3],
        ["id": "ord-008", "status": "completed", "category": "Electronics", "amount": 650.0, "quantity": 2],
        ["id": "ord-009", "status": "pending", "category": "Books", "amount": 78.0, "quantity": 5],
        ["id": "ord-010", "status": "cancelled", "category": "Electronics", "amount": 340.0, "quantity": 1],
        ["id": "ord-011", "status": "completed", "category": "Clothing", "amount": 210.0, "quantity": 2],
        ["id": "ord-012", "status": "completed", "category": "Books", "amount": 56.0, "quantity": 4],
        ["id": "ord-013", "status": "pending", "category": "Clothing", "amount": 175.0, "quantity": 1],
        ["id": "ord-014", "status": "completed", "category": "Electronics", "amount": 1800.0, "quantity": 1],
        ["id": "ord-015", "status": "completed", "category": "Books", "amount": 23.0, "quantity": 2],
    ]
}
