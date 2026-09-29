#if os(iOS)
import SwiftUI
import UIKit

/// Puts the keyboard away on a tap anywhere in the feed: beside a bubble, on one, or above them. Telegram-iOS adds one
/// tap recognizer to its whole history list (`ChatControllerNode.swift`); this adds a UIKit one to the feed's scroll
/// view. A SwiftUI tap gesture on the ScrollView missed taps on iOS 18.
///
/// It recognizes alongside everything else and lets touches through, so a tap on a link still opens it. Goes in the
/// background of the scroll content. The search results list, which covers the feed, uses it too.
struct FeedTapToDismiss: UIViewRepresentable {
    var isEnabled: Bool
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> AnchorView {
        AnchorView(recognizer: context.coordinator.recognizer)
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.action = action
        context.coordinator.recognizer.isEnabled = isEnabled
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void
        let recognizer = UITapGestureRecognizer()

        init(action: @escaping () -> Void) {
            self.action = action
            super.init()
            recognizer.addTarget(self, action: #selector(tapped))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
        }

        @objc private func tapped() {
            action()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    /// Moves the recognizer onto the enclosing scroll view whenever this view lands in a window.
    final class AnchorView: UIView {
        let recognizer: UITapGestureRecognizer

        init(recognizer: UITapGestureRecognizer) {
            self.recognizer = recognizer
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view = superview
            while let candidate = view, !(candidate is UIScrollView) { view = candidate.superview }
            guard let scrollView = view, recognizer.view !== scrollView else { return }
            recognizer.view?.removeGestureRecognizer(recognizer)
            scrollView.addGestureRecognizer(recognizer)
        }
    }
}
#endif
