#if os(macOS)
import AppKit
import SwiftUI

/// Runs Telegram for macOS's send transition on the NSScrollView behind the feed. SwiftUI can't do it itself:
/// its animated `scrollTo` on macOS ignores the requested duration and finishes in about 40ms.
///
/// Reproduces TelegramSwift's `TableAnimationInterface` behavior: snap to the bottom with no animation, then slide the
/// content up by the inserted height over 0.2s ease-out. A send during a running slide continues from where the
/// content is. Telegram animates each row's layer; SwiftUI rows have no layers of their own, so this gets the same
/// motion by animating the clip view's bounds instead.
@MainActor
final class FeedScroller {
    fileprivate weak var scrollView: NSScrollView?
    private var heightBeforeInsert: CGFloat?
    private var slideGeneration = 0
    private var isSliding = false

    static let slideDuration: TimeInterval = 0.2

    /// Call right before appending a message.
    func willInsert() {
        heightBeforeInsert = scrollView?.documentView?.frame.height
    }

    /// Call on the pass after appending, once the new row is laid out.
    func slideToBottom() {
        guard let scrollView, let documentView = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let inserted = max(0, documentView.frame.height - (heightBeforeInsert ?? documentView.frame.height))
        heightBeforeInsert = nil

        // Scrolled up (not just mid-slide): jump to where the bottom was, so only the new message's height animates.
        // The slide starts on the next pass so SwiftUI can draw the rows the jump revealed first.
        let direction: CGFloat = documentView.isFlipped ? 1 : -1
        let bottom = Self.bottomOrigin(of: clip, direction: direction)
        let remaining = (bottom.y - clip.bounds.minY) * direction
        if !isSliding, remaining > inserted {
            clip.setBoundsOrigin(NSPoint(x: bottom.x, y: bottom.y - inserted * direction))
            scrollView.reflectScrolledClipView(clip)
            isSliding = true
            Task { @MainActor in self.animate(clip, direction: direction) }
        } else {
            animate(clip, direction: direction)
        }
    }

    /// Lets the clip view clamp an out-of-range origin to the real bottom, content insets included.
    private static func bottomOrigin(of clip: NSClipView, direction: CGFloat) -> NSPoint {
        clip.constrainBoundsRect(NSRect(origin: NSPoint(x: clip.bounds.minX, y: 1e9 * direction), size: clip.bounds.size)).origin
    }

    private func animate(_ clip: NSClipView, direction: CGFloat) {
        let bottom = Self.bottomOrigin(of: clip, direction: direction)
        slideGeneration += 1
        let generation = slideGeneration
        isSliding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clip.animator().setBoundsOrigin(bottom)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if self?.slideGeneration == generation { self?.isSliding = false }
            }
        }
    }
}

/// Put inside the ScrollView's content to hand its NSScrollView to a `FeedScroller`.
struct FeedScrollerAnchor: NSViewRepresentable {
    let scroller: FeedScroller

    func makeNSView(context: Context) -> AnchorView {
        AnchorView(scroller: scroller)
    }

    func updateNSView(_ view: AnchorView, context: Context) {}

    final class AnchorView: NSView {
        let scroller: FeedScroller

        init(scroller: FeedScroller) {
            self.scroller = scroller
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scroller.scrollView = enclosingScrollView
        }
    }
}
#endif
