#if os(iOS)
import SwiftUI
import UIKit

/// Keeps the feed's scroll position where Telegram would as things around it change. SwiftUI changes the feed's bottom
/// inset and content size on its own but leaves the scroll position alone.
///
/// - The keyboard, or the composer growing a line, changes the bottom inset. Whatever the scroll position, the visible
///   messages move by exactly that much, as in Telegram-iOS's `ListView` inset fix. Only the ends clamp.
/// - Content that grows while the feed sits at the bottom, like a link preview arriving, is followed down with a short
///   slide, as `FeedScroller` does on the Mac. If the user is reading further up, it's left alone.
/// - Sending slides the new message up into view. From further up, the feed first jumps to where the bottom was.
/// - It tells the scroll-to-bottom button when to show, and scrolls for it.
@MainActor
@Observable
final class FeedFollower {
    /// Close to Telegram's 0.2s ease-out, like the Mac's `FeedScroller.sendResponse`.
    static let slideDuration: TimeInterval = 0.25
    /// How far above the newest message the feed has to be for the scroll-to-bottom button, as in Telegram-iOS.
    static let awayDistance: CGFloat = 40

    /// Whether the feed sits `awayDistance` or more above the newest message. Measured after this class's own moves, so
    /// a slide down to a new message or preview doesn't flash the button.
    private(set) var isAwayFromBottom = false

    @ObservationIgnored fileprivate weak var scrollView: UIScrollView? {
        didSet { resting = nil }
    }
    /// Where the feed last settled. SwiftUI applies a new inset, and clamps the offset to it, before this hears about
    /// it, so each move starts from here.
    @ObservationIgnored private var resting: Resting?
    @ObservationIgnored private var isInserting = false
    @ObservationIgnored private var isPrepending = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    private struct Resting {
        let offset: CGFloat
        let inset: CGFloat
        let contentHeight: CGFloat
        let isAtBottom: Bool
    }

    init() {
        // UIKit posts this inside the keyboard's animation block, so a scroll made here follows the keyboard's own
        // curve, the one SwiftUI moves the composer with. On hide, the notification's duration can say 0; the block
        // still animates. SwiftUI's own observer has already applied the new inset by now.
        observer = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    /// Call right before sending a message. The slide starts once the new row is laid out.
    func willInsert() {
        isInserting = true
    }

    /// Call right before older messages load above what's shown. They don't pull the feed down.
    func willPrepend() {
        isPrepending = true
    }

    /// Also call whenever the feed's scroll geometry changes, with SwiftUI's content height. The scroll view's own
    /// `contentSize` catches up a frame later, so growth would go unseen there.
    func update(contentHeight: CGFloat? = nil) {
        guard let scrollView else { return }
        let insets = scrollView.adjustedContentInset
        let height = contentHeight ?? resting?.contentHeight ?? scrollView.contentSize.height
        let top = -insets.top
        let bottom = max(top, height + insets.bottom - scrollView.bounds.height)
        // A finger on the feed owns the scroll position.
        if let resting, !scrollView.isDragging {
            let grown = height - resting.contentHeight
            if grown > 0, isPrepending {
                isPrepending = false
            } else if grown > 0, isInserting || resting.isAtBottom {
                isInserting = false
                slide(scrollView, to: bottom, inserted: grown)
            } else if insets.bottom != resting.inset {
                scrollView.contentOffset.y = min(max(resting.offset + insets.bottom - resting.inset, top), bottom)
            }
        }
        let offset = scrollView.contentOffset.y
        resting = Resting(offset: offset, inset: insets.bottom, contentHeight: height, isAtBottom: offset >= bottom - 2)
        let isAway = bottom - offset >= Self.awayDistance
        if isAway != isAwayFromBottom { isAwayFromBottom = isAway }
    }

    /// Telegram-iOS's down button: 0.3s on its "slide" curve. From more than a screen away, the feed first jumps to a
    /// screen above the newest message, so the glide never covers more than a screen.
    func scrollToBottom() {
        guard let scrollView else { return }
        let insets = scrollView.adjustedContentInset
        let height = resting?.contentHeight ?? scrollView.contentSize.height
        let bottom = max(-insets.top, height + insets.bottom - scrollView.bounds.height)
        // Stops a fling in progress, which would otherwise carry on over the animation.
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        guard !UIAccessibility.isReduceMotionEnabled else {
            scrollView.contentOffset.y = bottom
            return
        }
        let screen = scrollView.bounds.height - insets.top - insets.bottom
        if bottom - scrollView.contentOffset.y > screen {
            scrollView.contentOffset.y = bottom - screen
        }
        UIViewPropertyAnimator(duration: 0.3, controlPoint1: CGPoint(x: 0.33, y: 0.52), controlPoint2: CGPoint(x: 0.25, y: 0.99)) {
            scrollView.contentOffset.y = bottom
        }.startAnimation()
    }

    /// TelegramSwift's send transition: from further up, jump to where the bottom was, then slide up by what was added.
    private func slide(_ scrollView: UIScrollView, to bottom: CGFloat, inserted: CGFloat) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            scrollView.contentOffset.y = bottom
            return
        }
        if bottom - scrollView.contentOffset.y > inserted {
            scrollView.contentOffset.y = bottom - inserted
        }
        UIView.animate(springDuration: Self.slideDuration, bounce: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            scrollView.contentOffset.y = bottom
        }
    }
}

/// Finds the feed's scroll view for `FeedFollower`. Goes in the background of the scroll content.
struct FeedFollowerAnchor: UIViewRepresentable {
    let follower: FeedFollower

    func makeUIView(context: Context) -> AnchorView {
        AnchorView(follower: follower)
    }

    func updateUIView(_ view: AnchorView, context: Context) {}

    final class AnchorView: UIView {
        let follower: FeedFollower

        init(follower: FeedFollower) {
            self.follower = follower
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view = superview
            while let candidate = view, !(candidate is UIScrollView) { view = candidate.superview }
            follower.scrollView = view as? UIScrollView
        }
    }
}
#endif
