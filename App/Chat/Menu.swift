import SwiftUI

/// The panel behind Telegram's menus (`AppMenu` in TelegramSwift), used by the attach menu and a message's context
/// menu. It's as wide as its widest row, at least 100pt, with a 4pt gap above the first row and below the last.
struct MenuPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, 4)
        .frame(minWidth: 100)
        .fixedSize()
        .background(MenuBackground())
        .clipShape(.rect(cornerRadius: Metrics.menuRadius, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 4)
    }
}

/// Telegram blurs what's behind the menu (an `NSVisualEffectView`) and tints it with the theme's background.
private struct MenuBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Theme.menuTint
        }
    }
}

/// A menu row, laid out like TelegramSwift's `AppMenuRowItem`: an 18pt icon 15pt in from the panel's edge, the
/// title from 42pt, and a chevron 15pt from the far edge when the item has a submenu. It highlights on hover or when
/// the keyboard selects it, and shrinks slightly while pressed.
struct MenuRow: View {
    let title: String
    let systemImage: String
    var isDestructive = false
    var hasSubmenu = false
    var isHighlighted = false
    var onHover: (Bool) -> Void = { _ in }
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Sized to match Telegram's 18pt icons, measured from a screenshot.
                Image(systemName: systemImage)
                    .font(.system(size: 12.5))
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .padding(.leading, 9)
                Spacer(minLength: 0)
                if hasSubmenu {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 6)
                        .padding(.leading, 11)
                }
            }
            .foregroundStyle(isDestructive ? Theme.destructive : Theme.text)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background {
                // Appears at once, as in Telegram, where menu rows don't animate their highlight.
                if isHighlighted {
                    Capsule().fill(Theme.menuHighlight)
                }
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
        .onHover(perform: onHover)
    }
}

/// A 1pt line in a 5pt gap between groups of rows, inset 15pt from the panel's edges.
struct MenuSeparator: View {
    var body: some View {
        Theme.menuSeparator
            .frame(height: 1)
            .padding(.horizontal, 15)
            .padding(.vertical, 2)
    }
}

/// Telegram scales a menu row to 0.97 while the mouse is down on it.
private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.3), value: configuration.isPressed)
    }
}

/// Puts a menu's top-left corner at `point`, where TelegramSwift's `AppMenu` opens: at the pointer. Near the right edge
/// it opens to the left of the point instead, and near the bottom it moves up, so it stays inside the container.
struct MenuPlacement: Layout {
    var point: CGPoint
    var margin: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let menu = subviews.first else { return }
        let size = menu.sizeThatFits(.unspecified)
        let pointer = CGPoint(x: bounds.minX + point.x + 2, y: bounds.minY + point.y)
        var x = pointer.x + size.width <= bounds.maxX - margin ? pointer.x : pointer.x - size.width
        var y = min(pointer.y, bounds.maxY - margin - size.height)
        x = max(x, bounds.minX + margin)
        y = max(y, bounds.minY + margin)
        menu.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
    }
}
