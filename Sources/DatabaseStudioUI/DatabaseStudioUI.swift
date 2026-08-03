// DatabaseStudioUI
// UI層（SwiftUI・macOS専用）+ ロジック層統合

import SwiftUI

@_exported import DatabaseEngine
@_exported import DatabaseKit

/// DatabaseTypes (re-exported by DatabaseKit) declares its own `UUID`;
/// Studio persists and displays Foundation's.
public typealias UUID = Foundation.UUID
