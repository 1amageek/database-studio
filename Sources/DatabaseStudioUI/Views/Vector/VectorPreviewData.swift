import Foundation

/// Vector Preview 用サンプルデータ
enum VectorPreviewData {

    static let document: VectorDocument = {
        var doc = VectorDocument(
            points: points,
            entityName: "Product",
            embeddingField: "embedding",
            dimensions: 8,
            fieldNames: ["category", "price", "name"]
        )
        return doc
    }()

    /// 8次元の簡易埋め込みデータ（3クラスタ、決定的）
    ///
    /// ランダムではなく固定のジッターを使用し、プレビューの一貫性を確保
    static let points: [VectorPoint] = {
        var result: [VectorPoint] = []

        // 決定的ジッターテーブル（8次元 × 最大8ポイント分）
        let jitterTable: [[Float]] = [
            [ 0.08, -0.05,  0.12, -0.03,  0.07, -0.11,  0.04,  0.09],
            [-0.06,  0.10, -0.04,  0.08, -0.12,  0.03,  0.11, -0.07],
            [ 0.11, -0.08,  0.05,  0.13, -0.02, -0.09,  0.06, -0.10],
            [-0.03,  0.14, -0.07, -0.05,  0.10,  0.06, -0.13,  0.04],
            [ 0.09, -0.11,  0.08,  0.02, -0.06,  0.13, -0.05,  0.07],
            [-0.12,  0.04,  0.10, -0.09,  0.05, -0.02,  0.08, -0.14],
            [ 0.05,  0.07, -0.13,  0.06, -0.08,  0.11, -0.03,  0.12],
            [-0.09,  0.02,  0.06, -0.11,  0.14, -0.07,  0.09, -0.04],
        ]

        // クラスタ1: Electronics（正方向）
        let electronicsBase: [Float] = [0.8, 0.6, 0.2, -0.1, 0.3, 0.1, -0.2, 0.5]
        for i in 0..<8 {
            let embedding = zip(electronicsBase, jitterTable[i]).map { $0 + $1 }
            result.append(VectorPoint(
                id: "prod-e\(i)",
                embedding: embedding,
                fields: ["category": "Electronics", "price": "\(100 + i * 50)", "name": "Gadget \(i + 1)"],
                label: "Gadget \(i + 1)"
            ))
        }

        // クラスタ2: Books（負方向）
        let booksBase: [Float] = [-0.5, 0.7, -0.3, 0.6, -0.1, 0.4, 0.2, -0.3]
        for i in 0..<6 {
            let embedding = zip(booksBase, jitterTable[i]).map { $0 + $1 }
            result.append(VectorPoint(
                id: "prod-b\(i)",
                embedding: embedding,
                fields: ["category": "Books", "price": "\(15 + i * 5)", "name": "Book \(i + 1)"],
                label: "Book \(i + 1)"
            ))
        }

        // クラスタ3: Clothing（混合方向）
        let clothingBase: [Float] = [0.1, -0.4, 0.7, 0.3, -0.5, -0.2, 0.6, 0.1]
        for i in 0..<6 {
            let embedding = zip(clothingBase, jitterTable[i]).map { $0 + $1 }
            result.append(VectorPoint(
                id: "prod-c\(i)",
                embedding: embedding,
                fields: ["category": "Clothing", "price": "\(30 + i * 20)", "name": "Wear \(i + 1)"],
                label: "Wear \(i + 1)"
            ))
        }

        return result
    }()
}
