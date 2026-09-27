#if os(macOS)
import AppKit
import SwiftUI

/// Scrolls the feed with a critically damped spring stepped by the display's refresh (CADisplayLink), instead of
/// SwiftUI's animated `scrollTo`, which on macOS ignores the requested duration and finishes in about 40ms.
///
/// - Sending reproduces TelegramSwift's transition (`TableAnimationInterface`): if scrolled up, jump to where the
///   bottom was, then the content slides up by the inserted height. A send mid-slide re-targets the spring from its
///   current value and velocity, so rapid sends chain without a kink.
/// - Jumps (search results, calendar) glide to the row. Long jumps first snap to one screen away.
/// - Content that grows while the feed sits at the bottom, like a link preview arriving, is followed down. If the user
///   is reading further up, it's left alone.
/// - Anything else moving the scroll view, like the user's trackpad, cancels the animation. Reduce Motion skips it.
@MainActor
final class FeedScroller: NSObject {
    static let contentSpace = "feedContent"
    /// Close to Telegram's 0.2s ease-out: about 95% there after 0.19s.
    static let sendResponse: CGFloat = 0.25
    static let jumpResponse: CGFloat = 0.4

    /// Row frames in the feed's content space, by `FeedItem.id`. Rows report them as they're laid out.
    var rowFrames: [String: CGRect] = [:]

    fileprivate weak var scrollView: NSScrollView?
    fileprivate weak var contentAnchor: NSView?

    private var documentObserver: NSObjectProtocol?
    private var knownDocumentHeight: CGFloat?
    private var heightBeforeInsert: CGFloat?
    private var heightBeforePrepend: CGFloat?
    /// A jump to a row that hasn't been laid out yet, such as one in a page of history that's still loading.
    private var pendingJump: (id: String, anchor: UnitPoint)?
    private var framesWaitingForJump = 0
    private var framesWaitingForInsert = 0
    private var spring: Spring?
    private var displayLink: CADisplayLink?
    private var lastSetY: CGFloat?

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Call right before appending a message. The slide starts on the first frame after the new row is laid out.
    func willInsert() {
        guard let documentView = scrollView?.documentView else { return }
        heightBeforeInsert = documentView.frame.height
        framesWaitingForInsert = 0
        startDisplayLink()
    }

    /// Call right before older messages load above what's shown. What's on screen stays where it is.
    func willPrepend() {
        heightBeforePrepend = scrollView?.documentView?.frame.height
    }

    /// Glides the row with this `FeedItem.id` to `anchor` of the visible area (`.center`, `.top`, ...). A row that
    /// hasn't been laid out yet is jumped to once it has. Returns false only if there's no scroll view to drive.
    @discardableResult
    func scroll(toRow id: String, anchor: UnitPoint) -> Bool {
        guard let scrollView, let documentView = scrollView.documentView, documentView.isFlipped, let contentAnchor else {
            return false
        }
        guard let frame = rowFrames[id] else {
            pendingJump = (id, anchor)
            framesWaitingForJump = 0
            startDisplayLink()
            return true
        }
        pendingJump = nil
        let clip = scrollView.contentView
        let insets = scrollView.contentInsets
        let visibleHeight = clip.bounds.height - insets.top - insets.bottom
        let contentTop = contentAnchor.convert(contentAnchor.bounds, to: documentView).minY
        let rowY = contentTop + frame.minY + frame.height * anchor.y
        let target = clamped(rowY - insets.top - visibleHeight * anchor.y, in: clip)

        if reduceMotion {
            stop()
            set(target)
            return true
        }
        let current = currentState().value
        if spring == nil, abs(target - current) > visibleHeight {
            set(target - visibleHeight * (target > current ? 1 : -1))
        }
        animate(to: target, response: Self.jumpResponse)
        return true
    }

    /// Where a mouse event landed in the feed's content space, where `rowFrames` are. Nil if it landed on something
    /// over the feed instead, like the header, the composer or the search panel.
    func contentPoint(of event: NSEvent) -> CGPoint? {
        guard let scrollView, let documentView = scrollView.documentView, documentView.isFlipped, let contentAnchor,
              let frameView = scrollView.window?.contentView?.superview,
              frameView.hitTest(event.locationInWindow)?.isDescendant(of: scrollView) == true
        else { return nil }
        // The header and composer float over the ends of the feed, in its content insets.
        let clip = scrollView.contentView
        let inClip = clip.convert(event.locationInWindow, from: nil)
        let insets = scrollView.contentInsets
        guard inClip.y >= clip.bounds.minY + insets.top, inClip.y <= clip.bounds.maxY - insets.bottom else { return nil }
        let point = documentView.convert(event.locationInWindow, from: nil)
        let content = contentAnchor.convert(contentAnchor.bounds, to: documentView)
        return CGPoint(x: point.x - content.minX, y: point.y - content.minY)
    }

    // MARK: - Following growth

    fileprivate func attach(to scrollView: NSScrollView?, contentAnchor: NSView) {
        self.scrollView = scrollView
        self.contentAnchor = contentAnchor
        if let documentObserver { NotificationCenter.default.removeObserver(documentObserver) }
        documentObserver = nil
        guard let documentView = scrollView?.documentView else { return }
        documentView.postsFrameChangedNotifications = true
        knownDocumentHeight = documentView.frame.height
        documentObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: documentView, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.documentDidResize() }
        }
    }

    /// Runs during layout, so it only starts the spring; the scroll position moves on the next frame.
    private func documentDidResize() {
        guard let scrollView, let documentView = scrollView.documentView, documentView.isFlipped else { return }
        let height = documentView.frame.height
        defer { knownDocumentHeight = height }
        // Older messages went in above: shift by the added height so the visible ones don't move.
        if let before = heightBeforePrepend {
            heightBeforePrepend = nil
            if height > before {
                stop()
                set(scrollView.contentView.bounds.minY + height - before)
            }
            return
        }
        // Sends are handled by `willInsert`; live resizes rewrap text and shouldn't animate.
        guard let old = knownDocumentHeight, old > 0, height > old, heightBeforeInsert == nil, !scrollView.inLiveResize else {
            return
        }
        let clip = scrollView.contentView
        let oldBottom = old + scrollView.contentInsets.bottom - clip.bounds.height
        let heading = spring?.target ?? clip.bounds.minY
        guard heading >= oldBottom - 2 else { return }

        let bottom = clamped(.greatestFiniteMagnitude, in: clip)
        if reduceMotion {
            stop()
            set(bottom)
        } else {
            animate(to: bottom, response: Self.sendResponse)
        }
    }

    // MARK: - Animation

    private func beginSlide(inserted: CGFloat, in clip: NSClipView) {
        let bottom = clamped(.greatestFiniteMagnitude, in: clip)
        if reduceMotion {
            stop()
            set(bottom)
            return
        }
        if spring == nil, bottom - clip.bounds.minY > inserted {
            set(bottom - inserted)
        }
        animate(to: bottom, response: Self.sendResponse)
    }

    private func animate(to target: CGFloat, response: CGFloat) {
        let now = CACurrentMediaTime()
        let state = currentState(at: now)
        spring = Spring(target: target, from: state.value, velocity: state.velocity, start: now, response: response)
        startDisplayLink()
    }

    /// Where the scroll view is heading: the running spring's state, or where it sits now.
    private func currentState(at time: CFTimeInterval = CACurrentMediaTime()) -> (value: CGFloat, velocity: CGFloat) {
        if let spring { return spring.state(at: time) }
        return (scrollView?.contentView.bounds.minY ?? 0, 0)
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let scrollView, let documentView = scrollView.documentView, documentView.isFlipped else { return stop() }
        let clip = scrollView.contentView

        if let lastSetY, abs(clip.bounds.minY - lastSetY) > 0.5 {
            return stop() // the user (or a resize) moved it; let them have it
        }
        if let jump = pendingJump {
            if rowFrames[jump.id] != nil {
                scroll(toRow: jump.id, anchor: jump.anchor)
            } else {
                framesWaitingForJump += 1
                if framesWaitingForJump > 30 { pendingJump = nil }
                return
            }
        }
        if let heightBeforeInsert {
            let inserted = documentView.frame.height - heightBeforeInsert
            if inserted > 0 {
                self.heightBeforeInsert = nil
                beginSlide(inserted: inserted, in: clip)
            } else {
                framesWaitingForInsert += 1
                if framesWaitingForInsert > 10 { stop() }
                return
            }
        }
        guard let spring else { return stop() }
        let state = spring.state(at: link.targetTimestamp)
        if abs(state.value - spring.target) < 0.25, abs(state.velocity) < 10 {
            set(spring.target)
            stop()
        } else {
            set(state.value)
        }
    }

    private func set(_ y: CGFloat) {
        guard let scrollView else { return }
        let clip = scrollView.contentView
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
        lastSetY = clip.bounds.minY // after the clip view rounds it to the pixel grid
    }

    /// Lets the clip view clamp an origin to the scrollable range, content insets included.
    private func clamped(_ y: CGFloat, in clip: NSClipView) -> CGFloat {
        let y = min(max(y, -1e9), 1e9)
        return clip.constrainBoundsRect(NSRect(origin: NSPoint(x: clip.bounds.minX, y: y), size: clip.bounds.size)).minY
    }

    private func startDisplayLink() {
        guard displayLink == nil, let scrollView else { return }
        let link = scrollView.displayLink(target: self, selector: #selector(tick(_:)))
        // Without this the link can run far below the display's refresh rate.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate() // the link retains its target until invalidated
        displayLink = nil
        spring = nil
        lastSetY = nil
        heightBeforeInsert = nil
        pendingJump = nil
    }
}

/// A critically damped spring (damping ratio 1, so no overshoot) in closed form. It can be sampled at any timestamp
/// and re-targeted from its current value and velocity. `response` is Apple's: roughly how long it takes to get there.
private struct Spring {
    let target: CGFloat
    let displacement: CGFloat
    let velocity: CGFloat
    let start: CFTimeInterval
    let omega: CGFloat

    init(target: CGFloat, from value: CGFloat, velocity: CGFloat, start: CFTimeInterval, response: CGFloat) {
        self.target = target
        self.displacement = value - target
        self.velocity = velocity
        self.start = start
        self.omega = 2 * .pi / response
    }

    func state(at time: CFTimeInterval) -> (value: CGFloat, velocity: CGFloat) {
        let t = CGFloat(max(0, time - start))
        let b = velocity + omega * displacement
        let decay = exp(-omega * t)
        return (target + (displacement + b * t) * decay, (velocity - omega * b * t) * decay)
    }
}

/// Put behind the feed's content to hand its NSScrollView, and the content's position in it, to a `FeedScroller`.
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
            scroller.attach(to: enclosingScrollView, contentAnchor: self)
        }
    }
}
#endif
