import Foundation
import Accelerate

/// PCA による2D投影
///
/// Reference: Jolliffe, I.T., "Principal Component Analysis", Springer, 2002
/// 実装: Accelerate フレームワークの vDSP / LAPACK / BLAS を使用
enum PCAProjection {

    /// 高次元ベクトル群を2D平面に投影
    /// - Parameters:
    ///   - vectors: N個の D次元ベクトル
    /// - Returns: N個の 2D座標
    static func project(vectors: [[Float]]) -> [CGPoint] {
        guard !vectors.isEmpty else { return [] }
        let n = vectors.count
        let d = vectors[0].count
        guard d >= 2 else {
            return vectors.map { v in
                CGPoint(x: CGFloat(v.first ?? 0), y: CGFloat(v.count > 1 ? v[1] : 0))
            }
        }

        // 1. データ行列を構築（row-major: n × d）
        var matrix = [Float](repeating: 0, count: n * d)
        for i in 0..<n {
            let row = vectors[i]
            matrix.replaceSubrange(i * d ..< i * d + d, with: row)
        }

        // 2. 中心化（各次元の平均を引く）— vDSP で高速化
        var means = [Float](repeating: 0, count: d)
        matrix.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            for j in 0..<d {
                // stride=d でカラム方向の平均を計算
                vDSP_meanv(base + j, vDSP_Stride(d), &means[j], vDSP_Length(n))
            }
        }
        for i in 0..<n {
            for j in 0..<d {
                matrix[i * d + j] -= means[j]
            }
        }

        // 3. 共分散行列（d × d）の計算: C = X^T × X / (n-1)
        // d が小さい場合は直接計算、大きい場合は Power Iteration で上位2成分のみ
        if d <= 64 {
            return projectViaCovarianceMatrix(matrix: matrix, n: n, d: d)
        } else {
            return projectViaPowerIteration(matrix: matrix, n: n, d: d)
        }
    }

    // MARK: - 共分散行列 + 固有値分解（小次元向け）

    private static func projectViaCovarianceMatrix(matrix: [Float], n: Int, d: Int) -> [CGPoint] {
        // 共分散行列 C = X^T × X / (n-1) — BLAS sgemm で計算
        var cov = [Float](repeating: 0, count: d * d)
        var alpha: Float = 1.0 / Float(max(n - 1, 1))
        var beta: Float = 0.0

        // C = alpha * X^T * X + beta * C (column-major のため転置指定に注意)
        // matrix は row-major (n×d) = column-major では (d×n)^T
        cblas_sgemm(
            CblasRowMajor, CblasTrans, CblasNoTrans,
            Int32(d), Int32(d), Int32(n),
            alpha,
            matrix, Int32(d),
            matrix, Int32(d),
            beta,
            &cov, Int32(d)
        )

        // 固有値分解（LAPACK ssyev）
        var eigenvalues = [Float](repeating: 0, count: d)
        var lwork = __CLPK_integer(max(3 * d - 1, 1))
        var work = [Float](repeating: 0, count: Int(lwork))
        var dim = __CLPK_integer(d)
        var lda = __CLPK_integer(d)
        var info: __CLPK_integer = 0
        var jobz: Int8 = Int8(UnicodeScalar("V").value)
        var uplo: Int8 = Int8(UnicodeScalar("U").value)

        // 最適 work サイズを問い合わせ
        var queryLwork: __CLPK_integer = -1
        var workOpt: Float = 0
        ssyev_(&jobz, &uplo, &dim, &cov, &lda, &eigenvalues, &workOpt, &queryLwork, &info)
        if info == 0 {
            lwork = __CLPK_integer(workOpt)
            work = [Float](repeating: 0, count: Int(lwork))
        }

        // 実際の固有値分解
        dim = __CLPK_integer(d)
        lda = __CLPK_integer(d)
        info = 0
        ssyev_(&jobz, &uplo, &dim, &cov, &lda, &eigenvalues, &work, &lwork, &info)

        guard info == 0 else {
            // フォールバック: 最初の2次元を使用
            return (0..<n).map { i in
                CGPoint(x: CGFloat(matrix[i * d]), y: CGFloat(matrix[i * d + 1]))
            }
        }

        // 上位2固有ベクトル（最大固有値のカラム: 末尾2列）
        // cov は column-major に固有ベクトルを格納 (d × d)
        let pc1Col = d - 1
        let pc2Col = d - 2

        // 投影: projected = X × V[:, top2] — BLAS sgemv で各成分を計算
        var xCoords = [Float](repeating: 0, count: n)
        var yCoords = [Float](repeating: 0, count: n)

        // PC1: X × v1
        var one: Float = 1.0
        var zero: Float = 0.0
        // ssyev_ は column-major で固有ベクトルを格納: element (i, k) = cov[i + k * d]
        var v1 = [Float](repeating: 0, count: d)
        for j in 0..<d { v1[j] = cov[j + pc1Col * d] }
        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(n), Int32(d),
                     one, matrix, Int32(d), v1, 1, zero, &xCoords, 1)

        // PC2: X × v2
        var v2 = [Float](repeating: 0, count: d)
        for j in 0..<d { v2[j] = cov[j + pc2Col * d] }
        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(n), Int32(d),
                     one, matrix, Int32(d), v2, 1, zero, &yCoords, 1)

        return (0..<n).map { i in
            CGPoint(x: CGFloat(xCoords[i]), y: CGFloat(yCoords[i]))
        }
    }

    // MARK: - Power Iteration（高次元向け）

    private static func projectViaPowerIteration(matrix: [Float], n: Int, d: Int) -> [CGPoint] {
        // X^T × X × v の power iteration で上位2固有ベクトルを近似
        // BLAS で行列ベクトル積を高速化

        func matVecProduct(_ v: [Float]) -> [Float] {
            // result = X^T × (X × v)
            // Step 1: xv = X × v (n次元)
            var xv = [Float](repeating: 0, count: n)
            var one: Float = 1.0
            var zero: Float = 0.0
            cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(n), Int32(d),
                         one, matrix, Int32(d), v, 1, zero, &xv, 1)

            // Step 2: result = X^T × xv (d次元)
            var result = [Float](repeating: 0, count: d)
            cblas_sgemv(CblasRowMajor, CblasTrans, Int32(n), Int32(d),
                         one, matrix, Int32(d), xv, 1, zero, &result, 1)
            return result
        }

        func normalize(_ v: inout [Float]) -> Float {
            var norm: Float = 0
            vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
            norm = sqrt(norm)
            guard norm > 0 else { return 0 }
            var invNorm = 1.0 / norm
            vDSP_vsmul(v, 1, &invNorm, &v, 1, vDSP_Length(v.count))
            return norm
        }

        func orthogonalize(_ v: inout [Float], against u: [Float]) {
            var dot: Float = 0
            vDSP_dotpr(v, 1, u, 1, &dot, vDSP_Length(v.count))
            var negDot = -dot
            vDSP_vsma(u, 1, &negDot, v, 1, &v, 1, vDSP_Length(v.count))
        }

        // PC1
        // 決定的な初期ベクトル
        var v1 = [Float](repeating: 0, count: d)
        for i in 0..<d { v1[i] = Float(i % 2 == 0 ? 1 : -1) / Float(d) }
        _ = normalize(&v1)
        for _ in 0..<100 {
            v1 = matVecProduct(v1)
            _ = normalize(&v1)
        }

        // PC2
        var v2 = [Float](repeating: 0, count: d)
        for i in 0..<d { v2[i] = Float(i % 3 == 0 ? 1 : (i % 3 == 1 ? -1 : 0)) / Float(d) }
        _ = normalize(&v2)
        for _ in 0..<100 {
            v2 = matVecProduct(v2)
            orthogonalize(&v2, against: v1)
            _ = normalize(&v2)
        }

        // 投影 — BLAS sgemv
        var xCoords = [Float](repeating: 0, count: n)
        var yCoords = [Float](repeating: 0, count: n)
        var one: Float = 1.0
        var zero: Float = 0.0

        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(n), Int32(d),
                     one, matrix, Int32(d), v1, 1, zero, &xCoords, 1)
        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(n), Int32(d),
                     one, matrix, Int32(d), v2, 1, zero, &yCoords, 1)

        return (0..<n).map { i in
            CGPoint(x: CGFloat(xCoords[i]), y: CGFloat(yCoords[i]))
        }
    }

    // MARK: - コサイン類似度

    /// 2つのベクトルのコサイン類似度
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    /// L2 距離
    static func l2Distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return Float.infinity }
        var diff = [Float](repeating: 0, count: a.count)
        vDSP_vsub(b, 1, a, 1, &diff, 1, vDSP_Length(a.count))
        var sumSq: Float = 0
        vDSP_svesq(diff, 1, &sumSq, vDSP_Length(diff.count))
        return sqrt(sumSq)
    }
}
