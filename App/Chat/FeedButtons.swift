import SwiftUI

/// Round buttons floating over the feed's bottom-trailing corner, in the composer buttons' column. A hidden button's
/// slot closes, so the one above slides down into it.
/// - Scroll to the newest message, once the feed is far enough above it.
/// - iOS only, while stepping through search results in the chat: the older and newer result, as in Telegram-iOS. Its
///   down arrow scrolls to the bottom from the newest result, so it stands in for Scroll to Bottom.
/// - iOS only, above them: put the keyboard away while the keyboard is up. Telegram has no such button.
///
/// iOS copies Telegram-iOS's `ChatHistoryNavigationButtons`, the Mac TelegramSwift's `ChatNavigationScroller`.
struct FeedButtons: View {
    var showsScrollToBottom: Bool
    var showsHideKeyboard = false
    var searchArrows: SearchArrows?
    var onScrollToBottom: () -> Void
    var onHideKeyboard: () -> Void = {}

    struct SearchArrows {
        var canShowOlder: Bool
        var onOlder: () -> Void
        /// The newer result, or the bottom from the newest.
        var onNewer: () -> Void
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(macOS)
    /// TelegramSwift fades the button in and out over 0.2s, without scaling it.
    static let animation = Animation.easeOut(duration: 0.2)
    /// From the bottom of the button to the top of the composer's field.
    private static let gap: CGFloat = 18
    private static let chevronWidth: CGFloat = 1
    #else
    /// Telegram-iOS's 0.3s "spring", which is really this Bézier curve (`CAAnimationUtils`).
    static let animation = Animation.timingCurve(0.38, 0.7, 0.125, 1, duration: 0.3)
    private static let gap: CGFloat = 12
    private static let chevronWidth: CGFloat = 1.5
    #endif

    var body: some View {
        VStack(spacing: 12) {
            if showsHideKeyboard {
                button("Hide Keyboard", action: onHideKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.floatingButtonIcon)
                }
            }
            if let searchArrows {
                // Telegram-iOS dims a disabled arrow's icon to half.
                button("Older Result", action: searchArrows.onOlder) { chevron.rotationEffect(.degrees(180)) }
                    .disabled(!searchArrows.canShowOlder)
                    .opacity(searchArrows.canShowOlder ? 1 : 0.5)
                button("Newer Result", action: searchArrows.onNewer) { chevron }
            } else if showsScrollToBottom {
                button("Scroll to Bottom", action: onScrollToBottom) { chevron }
            }
        }
        .animation(Self.animation, value: showsScrollToBottom)
        .animation(Self.animation, value: searchArrows != nil)
        // The composer's field sits 4pt below the top of its inset.
        .padding(.bottom, Self.gap - 4)
        .padding(.trailing, Metrics.sideMargin)
    }

    /// Telegram's chevron: 18×9, sitting 1.5pt below center.
    private var chevron: some View {
        DownChevron()
            .stroke(Theme.floatingButtonIcon, lineWidth: Self.chevronWidth)
            .frame(width: 18, height: 9)
            .offset(y: 1.5)
    }

    private func button(_ label: LocalizedStringKey, action: @escaping () -> Void, @ViewBuilder icon: () -> some View) -> some View {
        Button(action: action) {
            icon()
                .frame(width: Metrics.chromeHeight, height: Metrics.chromeHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.pressFeedback)
        .chromeBackground(Circle())
        #if os(macOS)
        // TelegramSwift's shadow: blur 5, black at 0.1, 2pt down.
        .shadow(color: .black.opacity(0.1), radius: 2.5, y: 2)
        #endif
        .accessibilityLabel(label)
        .transition(transition.animation(Self.animation))
    }

    private var transition: AnyTransition {
        #if os(macOS)
        .opacity
        #else
        // Telegram-iOS grows a button in from a fifth of its size while fading it in, and shrinks it back out.
        reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity)
        #endif
    }
}

private struct DownChevron: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
    }
}
