import SwiftUI
import AppKit

/// SwiftUI コンテンツを NSView の子としてホストし、
/// レスポンダチェーンで伝播した scrollWheel / magnify を処理するラッパー。
///
/// ```
/// CanvasHostView (NSView) <- scrollWheel / magnify をここで処理
///   └── NSHostingView
///         └── Content (SwiftUI)
/// ```
///
/// SwiftUI の Canvas や NodeView は scrollWheel を消費しないため、
/// イベントはレスポンダチェーン経由でこの親 NSView まで到達する。
struct CanvasHostView<Content: View>: NSViewRepresentable {
    let onScroll: @MainActor (CGFloat, CGFloat) -> Void
    let onMagnify: @MainActor (CGFloat, CGPoint) -> Void
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> CanvasNSView {
        let nsView = CanvasNSView()
        nsView.clipsToBounds = true
        nsView.onScroll = onScroll
        nsView.onMagnify = onMagnify

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        nsView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: nsView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
        ])
        context.coordinator.hostingView = hosting
        return nsView
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onMagnify = onMagnify
        context.coordinator.hostingView?.rootView = content
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var hostingView: NSHostingView<Content>?
    }
}

/// scrollWheel と magnify を処理する NSView
final class CanvasNSView: NSView {
    var onScroll: (@MainActor (CGFloat, CGFloat) -> Void)?
    var onMagnify: (@MainActor (CGFloat, CGPoint) -> Void)?

    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let dx: CGFloat
        let dy: CGFloat
        if event.hasPreciseScrollingDeltas {
            dx = event.scrollingDeltaX
            dy = event.scrollingDeltaY
        } else {
            dx = event.scrollingDeltaX * 10
            dy = event.scrollingDeltaY * 10
        }
        MainActor.assumeIsolated {
            onScroll?(dx, dy)
        }
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        MainActor.assumeIsolated {
            onMagnify?(event.magnification, CGPoint(x: location.x, y: location.y))
        }
    }
}
