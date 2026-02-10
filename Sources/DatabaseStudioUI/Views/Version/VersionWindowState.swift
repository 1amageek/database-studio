import SwiftUI

/// Version History ウィンドウの共有状態
@Observable @MainActor
public final class VersionWindowState {
    public static let shared = VersionWindowState()

    public var document: VersionDocument?
    public var entityName: String = ""

    /// データソースからドキュメントを再取得するクロージャ
    public var refreshAction: (@MainActor () async -> VersionDocument?)?

    public init() {}
}
