import SwiftUI

/// Analytics ウィンドウの共有状態
@Observable @MainActor
public final class AnalyticsWindowState {
    public static let shared = AnalyticsWindowState()

    public var document: AnalyticsDocument?
    public var entityName: String = ""

    /// データソースからドキュメントを再取得するクロージャ
    public var refreshDocument: (@MainActor () async throws -> AnalyticsDocument?)?

    public init() {}
}
