#if os(iOS)
import SwiftUI
import UIKit

/// iOS: a message's context menu, built like Telegram-iOS's (`ContextControllerImpl`, `ContextGesture`) rather than
/// with the system's. Holding a bubble shrinks it a little; a moment later the menu opens over the blurred chat, with
/// the whole bubble lifted out of the feed and moved only as far as the actions need (`FeedContextMenuOverlay`).
///
/// The system menu kept a tall bubble inside its own margins and cut it off well short of the screen's edge. Before
/// that, SwiftUI's `.contextMenu` was rebuilt while it showed, on the device.
///
/// One long-press recognizer covers the feed, as Telegram's history list owns its menu. It finds the bubble under the
/// finger from the frames the bubbles report in the feed content's coordinates (`report`).
@MainActor
@Observable
final class FeedContextMenu: NSObject, UIGestureRecognizerDelegate {
    /// The feed content's coordinate space, which the bubble frames are in.
    nonisolated static let contentSpace = "FeedContextMenu.content"
    /// Telegram's `ContextGesture`: a held bubble starts to shrink after 0.12s, and the menu opens 0.2s later.
    static let pressDelay: TimeInterval = 0.12
    static let pressDuration: TimeInterval = 0.2

    /// An open menu, or one on its way out.
    struct Presentation: Identifiable {
        let message: Message
        let position: BubblePosition
        /// Where the bubble sat, in window coordinates.
        let frame: CGRect
        /// How far the press had shrunk the bubble. The copy springs back to full size from there.
        let pressScale: CGFloat
        /// The bubble's shade where it sat in the feed (`bubbleShade`).
        let shade: Double
        let safeArea: UIEdgeInsets

        var id: Message.ID { message.id }
    }

    /// The bubble a finger is holding, shrunk while its menu is about to open.
    private(set) var pressed: Message.ID?
    private(set) var presentation: Presentation?

    /// Finds a message the feed shows.
    @ObservationIgnored var message: (Message.ID) -> Message? = { _ in nil }
    /// Called as a menu opens.
    @ObservationIgnored var onOpen: () -> Void = {}
    @ObservationIgnored private var bubbles: [Message.ID: (frame: CGRect, position: BubblePosition)] = [:]
    @ObservationIgnored fileprivate weak var contentAnchor: UIView?
    @ObservationIgnored private weak var scrollView: UIScrollView?
    @ObservationIgnored private var recognizer: UILongPressGestureRecognizer?
    @ObservationIgnored private var pressStart: CGPoint = .zero
    /// The finger holding the bubble. Its other gestures are cancelled when the menu opens.
    @ObservationIgnored private weak var touch: UITouch?
    @ObservationIgnored private var openTask: Task<Void, Never>?

    /// Where a message's bubble is in the feed content. Rows call this when their layout changes, not while scrolling.
    func report(_ id: Message.ID, frame: CGRect, position: BubblePosition) {
        bubbles[id] = (frame, position)
    }

    func forget(_ id: Message.ID) {
        bubbles[id] = nil
    }

    /// Telegram shrinks a held bubble by 15pt across, and never below 70%.
    func pressScale(for id: Message.ID) -> CGFloat {
        guard pressed == id, let width = bubbles[id]?.frame.width, width > 0 else { return 1 }
        return max(0.7, (width - 15) / width)
    }

    /// The menu has finished animating out, so the bubble goes back to showing in the feed.
    func didClose() {
        presentation = nil
    }

    fileprivate func attach(to scrollView: UIScrollView, anchor: UIView) {
        contentAnchor = anchor
        guard self.scrollView !== scrollView else { return }
        if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        recognizer.minimumPressDuration = Self.pressDelay
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        scrollView.addGestureRecognizer(recognizer)
        self.recognizer = recognizer
        self.scrollView = scrollView
    }

    // MARK: - The press

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard presentation == nil, let anchor = contentAnchor, let id = bubble(at: recognizer.location(in: anchor)) else { return }
            pressStart = recognizer.location(in: nil)
            withAnimation(.linear(duration: Self.pressDuration)) { pressed = id }
            openTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.pressDuration))
                guard !Task.isCancelled else { return }
                self?.open(id)
            }
        case .changed:
            // A finger that moves is scrolling, as in Telegram's gesture.
            let point = recognizer.location(in: nil)
            if pressed != nil, hypot(point.x - pressStart.x, point.y - pressStart.y) > 10 { cancelPress() }
        default:
            if pressed != nil { cancelPress() }
        }
    }

    private func cancelPress() {
        openTask?.cancel()
        openTask = nil
        withAnimation(.easeOut(duration: Self.pressDuration)) { pressed = nil }
    }

    /// Opens a message's menu without a press, for VoiceOver.
    func openMenu(for id: Message.ID) {
        guard presentation == nil else { return }
        open(id)
    }

    private func open(_ id: Message.ID) {
        openTask = nil
        guard let bubble = bubbles[id], let message = message(id), let anchor = contentAnchor,
              let scrollView, let window = anchor.window
        else {
            pressed = nil
            return
        }
        // The finger is still down. Lifting it mustn't open a link or reload a preview under it, and moving it
        // mustn't scroll the feed, so everything else following it is cancelled, as the system's menu does.
        for other in touch?.gestureRecognizers ?? [scrollView.panGestureRecognizer] where other !== recognizer {
            other.isEnabled = false
            other.isEnabled = true
        }
        touch = nil
        let frame = anchor.convert(bubble.frame, to: nil)
        let viewport = scrollView.convert(scrollView.bounds, to: nil)
        let presentation = Presentation(
            message: message,
            position: bubble.position,
            frame: frame,
            pressScale: pressScale(for: id),
            shade: bubbleShade(midY: frame.midY - viewport.minY, height: viewport.height),
            safeArea: window.safeAreaInsets
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onOpen()
        self.presentation = presentation
        pressed = nil
    }

    private func bubble(at point: CGPoint) -> Message.ID? {
        bubbles.first { $0.value.frame.contains(point) }?.key
    }

    // MARK: - UIGestureRecognizerDelegate

    /// Only a press on a bubble starts; anywhere else the feed scrolls and taps as usual.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard presentation == nil, let anchor = contentAnchor else { return false }
        return bubble(at: gestureRecognizer.location(in: anchor)) != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        self.touch = touch
        return true
    }

    /// The feed still scrolls if the finger moves, and a quick press on a link still opens it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Attaches `FeedContextMenu` to the feed's scroll view. Goes in the background of the scroll content, whose
/// coordinate space is `FeedContextMenu.contentSpace`.
struct FeedContextMenuAnchor: UIViewRepresentable {
    let menu: FeedContextMenu

    func makeUIView(context: Context) -> AnchorView {
        AnchorView(menu: menu)
    }

    func updateUIView(_ view: AnchorView, context: Context) {}

    final class AnchorView: UIView {
        let menu: FeedContextMenu

        init(menu: FeedContextMenu) {
            self.menu = menu
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view = superview
            while let candidate = view, !(candidate is UIScrollView) { view = candidate.superview }
            if let scrollView = view as? UIScrollView { menu.attach(to: scrollView, anchor: self) }
        }
    }
}

extension EnvironmentValues {
    /// Where bubbles report their frames for the iOS context menu.
    @Entry var feedContextMenu: FeedContextMenu?
}
#endif
