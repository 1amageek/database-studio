import SwiftUI

/// Map ウィンドウの共有状態
@Observable @MainActor
public final class MapWindowState {
    public static let shared = MapWindowState()

    public var document: MapDocument?
    public var entityName: String = ""

    /// データソースからドキュメントを再取得するクロージャ
    public var refreshAction: (@MainActor () async -> MapDocument?)?

    public init() {}
}
