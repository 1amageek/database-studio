import SwiftUI

/// Vector Explorer ウィンドウの共有状態
@Observable @MainActor
public final class VectorWindowState {
    public static let shared = VectorWindowState()

    public var document: VectorDocument?
    public var entityName: String = ""

    /// データソースからドキュメントを再取得するクロージャ
    public var refreshAction: (@MainActor () async -> VectorDocument?)?

    public init() {}
}
