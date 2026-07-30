import SwiftUI
import AppKit

/// Presents SwiftUI canvas content while handling gestures propagated through
/// the responder chain.
///
/// ```
/// CanvasInteractionView <- handles scrollWheel and magnify
///   └── NSHostingView
///         └── Content (SwiftUI)
/// ```
///
/// Canvas and its node views leave these gestures on the responder chain, so
/// the parent responder receives them without intercepting content interaction.
struct CanvasInteractionView<Content: View>: NSViewRepresentable {
    let onScroll: @MainActor (CGFloat, CGFloat) -> Void
    let onMagnify: @MainActor (CGFloat, CGPoint) -> Void
    var onNavigateBack: (@MainActor () -> Void)?
    var onNavigateForward: (@MainActor () -> Void)?
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> CanvasInteractionResponder {
        let interactionResponder = CanvasInteractionResponder()
        interactionResponder.clipsToBounds = true
        interactionResponder.onScroll = onScroll
        interactionResponder.onMagnify = onMagnify
        interactionResponder.onNavigateBack = onNavigateBack
        interactionResponder.onNavigateForward = onNavigateForward

        let presentedContent = NSHostingView(rootView: content)
        presentedContent.translatesAutoresizingMaskIntoConstraints = false
        interactionResponder.addSubview(presentedContent)
        NSLayoutConstraint.activate([
            presentedContent.leadingAnchor.constraint(equalTo: interactionResponder.leadingAnchor),
            presentedContent.trailingAnchor.constraint(equalTo: interactionResponder.trailingAnchor),
            presentedContent.topAnchor.constraint(equalTo: interactionResponder.topAnchor),
            presentedContent.bottomAnchor.constraint(equalTo: interactionResponder.bottomAnchor),
        ])
        context.coordinator.presentedContent = presentedContent
        return interactionResponder
    }

    func updateNSView(_ interactionResponder: CanvasInteractionResponder, context: Context) {
        interactionResponder.onScroll = onScroll
        interactionResponder.onMagnify = onMagnify
        interactionResponder.onNavigateBack = onNavigateBack
        interactionResponder.onNavigateForward = onNavigateForward
        context.coordinator.presentedContent?.rootView = content
    }

    func makeCoordinator() -> CanvasContentState { CanvasContentState() }

    final class CanvasContentState {
        var presentedContent: NSHostingView<Content>?
    }
}

/// Handles canvas scrolling, magnification, and backward or forward navigation.
final class CanvasInteractionResponder: NSView {
    var onScroll: (@MainActor (CGFloat, CGFloat) -> Void)?
    var onMagnify: (@MainActor (CGFloat, CGPoint) -> Void)?
    var onNavigateBack: (@MainActor () -> Void)?
    var onNavigateForward: (@MainActor () -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let horizontalDelta: CGFloat
        let verticalDelta: CGFloat
        if event.hasPreciseScrollingDeltas {
            horizontalDelta = event.scrollingDeltaX
            verticalDelta = event.scrollingDeltaY
        } else {
            horizontalDelta = event.scrollingDeltaX * 10
            verticalDelta = event.scrollingDeltaY * 10
        }
        MainActor.assumeIsolated {
            onScroll?(horizontalDelta, verticalDelta)
        }
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        MainActor.assumeIsolated {
            onMagnify?(event.magnification, CGPoint(x: location.x, y: location.y))
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        // Standard multi-button mice use button 3 for back and 4 for forward.
        switch event.buttonNumber {
        case 3:
            MainActor.assumeIsolated { onNavigateBack?() }
        case 4:
            MainActor.assumeIsolated { onNavigateForward?() }
        default:
            super.otherMouseUp(with: event)
        }
    }

    override func swipe(with event: NSEvent) {
        // Three-finger trackpad swipe.
        if event.deltaX > 0 {
            MainActor.assumeIsolated { onNavigateBack?() }
        } else if event.deltaX < 0 {
            MainActor.assumeIsolated { onNavigateForward?() }
        }
    }
}
