import SwiftUI

/// Routes explicit File commands to the focused base window.
@MainActor
public struct WorkspaceNavigation {
    public let open: (WorkspaceDestination) -> Void

    public init(open: @escaping (WorkspaceDestination) -> Void) { self.open = open }
}

private struct WorkspaceNavigationKey: FocusedValueKey {
    typealias Value = WorkspaceNavigation
}

extension FocusedValues {
    public var workspaceNavigation: WorkspaceNavigation? {
        get { self[WorkspaceNavigationKey.self] }
        set { self[WorkspaceNavigationKey.self] = newValue }
    }
}
