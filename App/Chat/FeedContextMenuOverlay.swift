#if os(iOS)
import SwiftUI
import UIKit

/// iOS: an open message menu, laid out and animated like Telegram-iOS's (`ContextControllerExtractedPresentationNode`).
///
/// The chat blurs and dims behind it. The bubble is lifted out of the feed whole and moves only up or down: into view
/// if it was under the header, and up far enough for the actions to fit 7pt below it. A bubble too tall for that opens
/// scrolled to its bottom, with its top cut off by the screen's edge, and the menu scrolls to show the rest. The actions
/// grow out from the bubble's old bottom edge.
struct FeedContextMenuOverlay: View {
    let presentation: FeedContextMenu.Presentation
    /// Called once the menu has animated out, with the item that was picked, if any.
    var onClose: (MessageMenuItem?) -> Void

    @Environment(\.chatTextSize) private var textSize
    @State private var isLifted = false
    @State private var isBackdropShown = false
    @State private var bubbleScale: CGFloat
    @State private var actionsScale: CGFloat = 0.01
    @State private var actionsOpacity = 0.0
    @State private var isClosing = false
    /// How far the menu is scrolled. Only a menu taller than the screen scrolls.
    @State private var scrollOffset: CGFloat?

    /// Telegram's spring for the bubble and the actions (mass 5, stiffness 900, damping 104): about 0.42s, barely
    /// overshooting.
    private static let spring = Animation.interpolatingSpring(mass: 5, stiffness: 900, damping: 104)
    /// The backdrop fading, and everything going back on close.
    private static let fade = Animation.easeInOut(duration: 0.2)

    init(presentation: FeedContextMenu.Presentation, onClose: @escaping (MessageMenuItem?) -> Void) {
        self.presentation = presentation
        self.onClose = onClose
        _bubbleScale = State(initialValue: presentation.pressScale)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = MenuLayout(
                bubble: presentation.frame.offsetBy(dx: -proxy.frame(in: .global).minX, dy: -proxy.frame(in: .global).minY),
                safeArea: presentation.safeArea,
                size: proxy.size,
                actions: ContextActionList.size(textSize: textSize.message)
            )
            ZStack {
                BlurBackdrop(isShown: isBackdropShown)
                // Telegram's `contextMenu.dimColor`.
                Theme.contextMenuDim.opacity(isBackdropShown ? 1 : 0)
                ScrollView {
                    content(layout, width: proxy.size.width)
                }
                .scrollDisabled(layout.overflow == 0)
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .noScrollEdgeEffect()
                .defaultScrollAnchor(.bottom)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                    scrollOffset = offset
                }
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: open)
    }

    private func content(_ layout: MenuLayout, width: CGFloat) -> some View {
        // Where the bubble sat in the feed, in the menu's scrolled content.
        let restingY = layout.bubble.minY + (scrollOffset ?? layout.overflow)
        return ZStack(alignment: .topLeading) {
            // A tap anywhere but the actions closes the menu, the bubble included.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { close(nil) }
            BubbleView(message: presentation.message, position: presentation.position)
                .environment(\.bubbleShade, presentation.shade)
                .frame(width: layout.bubble.width)
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
                .scaleEffect(bubbleScale)
                .offset(x: layout.bubble.minX, y: isLifted ? layout.liftedY : restingY)
            ContextActionList(textSize: textSize.message) { item in
                close(item)
            }
            .frame(width: layout.actions.width, height: layout.actions.height)
            // Grows out from the middle of the bubble's old bottom edge.
            .scaleEffect(actionsScale, anchor: UnitPoint(
                x: 0.5,
                y: (layout.bubble.height + restingY - layout.actions.minY) / max(layout.actions.height, 1)
            ))
            .opacity(actionsOpacity)
            .offset(x: layout.actions.minX, y: layout.actions.minY)
            .allowsHitTesting(!isClosing)
        }
        .frame(width: width, height: layout.contentHeight, alignment: .topLeading)
    }

    private func open() {
        withAnimation(Self.fade) { isBackdropShown = true }
        withAnimation(Self.spring) {
            isLifted = true
            actionsScale = 1
        }
        // The press shrank the bubble; it grows back while it moves.
        withAnimation(.easeOut(duration: 0.2)) { bubbleScale = 1 }
        withAnimation(.linear(duration: 0.05)) { actionsOpacity = 1 }
    }

    private func close(_ item: MessageMenuItem?) {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(Self.fade) {
            isBackdropShown = false
            isLifted = false
            bubbleScale = 1
            actionsScale = 0.01
            actionsOpacity = 0
        } completion: {
            onClose(item)
        }
    }
}

private extension View {
    /// iOS 26 blurs a scroll view's content under the status bar. Telegram's menu is cut off by the screen's edge only.
    @ViewBuilder func noScrollEdgeEffect() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}

/// Where everything goes, in the menu's scroll content, following `ContextControllerExtractedPresentationNode`.
private struct MenuLayout {
    /// The bubble where it sat in the feed, in the overlay's coordinates.
    let bubble: CGRect
    let liftedY: CGFloat
    let actions: CGRect
    let contentHeight: CGFloat
    /// How much taller the content is than the screen: where it opens scrolled to.
    let overflow: CGFloat

    /// Between the bubble and the actions.
    static let spacing: CGFloat = 7

    init(bubble: CGRect, safeArea: UIEdgeInsets, size: CGSize, actions: CGSize) {
        self.bubble = bubble
        let top = safeArea.top + 8
        let bottom = size.height - 10 - safeArea.bottom
        // Down into view if it was under the header, then up until the actions fit, but never above `top`.
        var y = max(bubble.minY, top)
        let blockBottom = y + bubble.height + Self.spacing + actions.height
        if blockBottom > bottom { y -= blockBottom - bottom }
        y = max(y, top)
        liftedY = y
        let actionsY = y + bubble.height + Self.spacing
        contentHeight = max(size.height, actionsY + actions.height + 10 + safeArea.bottom)
        overflow = contentHeight - size.height
        // The actions line up with the bubble's outer edge, on whichever side of the screen it sits, 12pt in at least.
        var x = bubble.midX > size.width / 2 ? bubble.maxX - 7 - actions.width : bubble.minX + 2
        x = min(max(x, 12), size.width - 12 - actions.width)
        self.actions = CGRect(origin: CGPoint(x: x, y: actionsY), size: actions)
    }
}

/// Telegram-iOS's actions list (`ContextControllerActionsStackNode`): rows 11pt above and below the title, in the
/// chat's text size, with the icon's 32pt column 20pt in and the title from 60pt. Groups are split by 20pt gaps with a
/// hairline. A pressed row lights up in a rounded rectangle inset 10pt.
private struct ContextActionList: View {
    let textSize: CGFloat
    var onSelect: (MessageMenuItem) -> Void

    private static let padding: CGFloat = 10
    private static let separatorHeight: CGFloat = 20
    private static let minWidth: CGFloat = 220

    private static func rowHeight(textSize: CGFloat) -> CGFloat {
        ceil(UIFont.systemFont(ofSize: textSize).lineHeight) + 22
    }

    /// Known before it's laid out, so the menu can place the bubble and the actions together.
    static func size(textSize: CGFloat) -> CGSize {
        let groups = MessageMenuItem.groups
        let rows = CGFloat(groups.joined().count)
        let height = padding * 2 + rows * rowHeight(textSize: textSize) + CGFloat(groups.count - 1) * separatorHeight
        let font = UIFont.systemFont(ofSize: textSize)
        let title = groups.joined().map { ceil(($0.title as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
        return CGSize(width: max(minWidth, 60 + title + 18), height: height)
    }

    var body: some View {
        let rowHeight = Self.rowHeight(textSize: textSize)
        VStack(spacing: 0) {
            ForEach(MessageMenuItem.groups.indices, id: \.self) { index in
                if index > 0 {
                    Theme.contextMenuSeparator
                        .frame(height: 1)
                        .padding(.horizontal, 18)
                        .frame(height: Self.separatorHeight)
                }
                ForEach(MessageMenuItem.groups[index]) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: 0) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 18))
                                .frame(width: 32)
                                .padding(.leading, 20)
                            Text(item.title)
                                .font(.system(size: textSize))
                                .lineLimit(1)
                                .padding(.leading, 8)
                            Spacer(minLength: 18)
                        }
                        .foregroundStyle(item.isDestructive ? Theme.contextMenuDestructive : Theme.text)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ContextActionStyle(cornerRadius: min(20, rowHeight / 2)))
                }
            }
        }
        .padding(.vertical, Self.padding)
        .background {
            GeometryReader { proxy in
                ContextActionBackground(shape: RoundedRectangle(cornerRadius: min(30, proxy.size.height / 2), style: .continuous))
            }
        }
    }
}

private struct ContextActionStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.contextMenuPressed.opacity(configuration.isPressed ? 1 : 0))
                    .padding(.horizontal, 10)
                    .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
            }
    }
}

/// Telegram's glass on iOS 26 and later. Before that, its panel over a blur, with a faint shadow.
private struct ContextActionBackground<S: Shape>: View {
    let shape: S

    var body: some View {
        if #available(iOS 26, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Theme.contextMenuFill)
            }
            .shadow(color: .black.opacity(0.04), radius: 20, y: 1)
        }
    }
}

/// The blur behind an open menu. The blur's radius animates in and out, as Telegram's does, rather than a finished
/// blur fading.
private struct BlurBackdrop: UIViewRepresentable {
    var isShown: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: nil)
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        guard context.coordinator.isShown != isShown else { return }
        context.coordinator.isShown = isShown
        let effect = isShown ? UIBlurEffect(style: .systemUltraThinMaterial) : nil
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            view.effect = effect
        }
    }

    final class Coordinator {
        var isShown = false
    }
}
#endif
