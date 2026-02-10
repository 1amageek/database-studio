import SwiftUI

/// 別ウィンドウで表示する Version History
public struct VersionWindowView: View {
    let state = VersionWindowState.shared

    public init() {}

    public var body: some View {
        if let document = state.document {
            VersionView(document: document)
                .navigationTitle("\(state.entityName) – Version History")
        } else {
            ContentUnavailableView(
                "No Version Data",
                systemImage: "clock.arrow.circlepath",
                description: Text("Open version history from a record with version tracking")
            )
        }
    }
}
