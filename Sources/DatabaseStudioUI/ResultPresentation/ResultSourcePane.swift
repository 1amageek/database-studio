import SwiftUI
import MacComponent

/// Keeps an optional query editor below the current result or execution status.
struct ResultSourcePane<Content: View>: View {
    private let sourceContent: AnyView?
    private let content: Content

    init(sourceContent: AnyView?, @ViewBuilder content: () -> Content) {
        self.sourceContent = sourceContent
        self.content = content()
    }

    var body: some View {
        if let sourceContent {
            VSplitPane {
                content
                sourceContent
            }
            .topPaneHeight(minimum: 200)
            .bottomPaneHeight(180, minimum: 80)
        } else {
            content
        }
    }
}
