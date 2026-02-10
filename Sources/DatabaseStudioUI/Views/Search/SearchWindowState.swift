import SwiftUI

/// Search ウィンドウの共有状態
@Observable @MainActor
public final class SearchWindowState {
    public static let shared = SearchWindowState()

    public var document: SearchDocument?
    public var entityName: String = ""

    /// データソースからドキュメントを再取得するクロージャ
    public var refreshAction: (@MainActor () async -> SearchDocument?)?

    public init() {}
}
