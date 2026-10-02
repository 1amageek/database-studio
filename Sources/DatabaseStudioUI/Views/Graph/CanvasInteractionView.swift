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
    var onThreeFingerOrbit: (@MainActor (CGFloat, CGFloat, CGFloat) -> Void)?
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> CanvasInteractionResponder {
        let interactionResponder = CanvasInteractionResponder()
        interactionResponder.clipsToBounds = true
        interactionResponder.onScroll = onScroll
        interactionResponder.onMagnify = onMagnify
        interactionResponder.onNavigateBack = onNavigateBack
        interactionResponder.onNavigateForward = onNavigateForward
        interactionResponder.onThreeFingerOrbit = onThreeFingerOrbit
        interactionResponder.allowedTouchTypes = onThreeFingerOrbit == nil ? [] : [.indirect]
        interactionResponder.wantsRestingTouches = onThreeFingerOrbit != nil

        let presentedContent = CanvasHostingView(rootView: content)
        presentedContent.translatesAutoresizingMaskIntoConstraints = false
        presentedContent.allowedTouchTypes = interactionResponder.allowedTouchTypes
        presentedContent.wantsRestingTouches = interactionResponder.wantsRestingTouches
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
        interactionResponder.onThreeFingerOrbit = onThreeFingerOrbit
        interactionResponder.allowedTouchTypes = onThreeFingerOrbit == nil ? [] : [.indirect]
        interactionResponder.wantsRestingTouches = onThreeFingerOrbit != nil
        context.coordinator.presentedContent?.allowedTouchTypes = interactionResponder.allowedTouchTypes
        context.coordinator.presentedContent?.wantsRestingTouches = interactionResponder.wantsRestingTouches
        context.coordinator.presentedContent?.rootView = content
    }

    static func dismantleNSView(_ interactionResponder: CanvasInteractionResponder, coordinator: CanvasContentState) {
        interactionResponder.onThreeFingerOrbit = nil
        interactionResponder.onScroll = nil
        interactionResponder.onMagnify = nil
        interactionResponder.onNavigateBack = nil
        interactionResponder.onNavigateForward = nil
        coordinator.presentedContent = nil
    }

    func makeCoordinator() -> CanvasContentState { CanvasContentState() }

    // Forward raw contacts explicitly rather than relying on SwiftUI gesture handling.
    final class CanvasHostingView: NSHostingView<Content> {
        override func touchesBegan(with event: NSEvent) { nextResponder?.touchesBegan(with: event) }
        override func touchesMoved(with event: NSEvent) { nextResponder?.touchesMoved(with: event) }
        override func touchesEnded(with event: NSEvent) { nextResponder?.touchesEnded(with: event) }
        override func touchesCancelled(with event: NSEvent) { nextResponder?.touchesCancelled(with: event) }
    }

    final class CanvasContentState {
        var presentedContent: NSHostingView<Content>?
    }
}

/// Handles canvas camera gestures and backward or forward navigation.
final class CanvasInteractionResponder: NSView {
    var onScroll: (@MainActor (CGFloat, CGFloat) -> Void)?
    var onMagnify: (@MainActor (CGFloat, CGPoint) -> Void)?
    var onNavigateBack: (@MainActor () -> Void)?
    var onNavigateForward: (@MainActor () -> Void)?

    var onThreeFingerOrbit: (@MainActor (CGFloat, CGFloat, CGFloat) -> Void)? {
        didSet {
            if onThreeFingerOrbit == nil {
                rotation.reset()
                isHandlingThreeFingerGesture = false
            }
        }
    }
    private var rotation = ThreeFingerRotation()
    private var isHandlingThreeFingerGesture = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard !isHandlingThreeFingerGesture else { return }
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
        guard !isHandlingThreeFingerGesture else { return }
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

    override func touchesBegan(with event: NSEvent) { updateRotation(with: event) }
    override func touchesMoved(with event: NSEvent) { updateRotation(with: event) }
    override func touchesEnded(with event: NSEvent) { updateRotation(with: event) }
    override func touchesCancelled(with event: NSEvent) {
        rotation.reset()
        isHandlingThreeFingerGesture = false
    }

    private func updateRotation(with event: NSEvent) {
        guard onThreeFingerOrbit != nil else { return }
        let touches = event.touches(matching: .touching, in: self)
        if touches.isEmpty { isHandlingThreeFingerGesture = false }
        guard touches.count == 3, let first = touches.first, let device = first.device as? NSObject else {
            rotation.reset()
            return
        }
        var contacts: [AnyHashable: CGPoint] = [:]
        for touch in touches {
            guard touch.type == .indirect, let otherDevice = touch.device as? NSObject,
                  device.isEqual(otherDevice), let identity = touch.identity as? AnyHashable else {
                rotation.reset()
                return
            }
            contacts[identity] = CGPoint(x: touch.normalizedPosition.x * touch.deviceSize.width,
                                         y: -touch.normalizedPosition.y * touch.deviceSize.height)
        }
        isHandlingThreeFingerGesture = true
        if let delta = rotation.update(contacts) {
            onThreeFingerOrbit?(delta.translation.width, delta.translation.height, delta.roll)
        }
    }

    override func swipe(with event: NSEvent) {
        guard onThreeFingerOrbit == nil else { return }
        // Three-finger trackpad swipe.
        if event.deltaX > 0 {
            MainActor.assumeIsolated { onNavigateBack?() }
        } else if event.deltaX < 0 {
            MainActor.assumeIsolated { onNavigateForward?() }
        }
    }
}
