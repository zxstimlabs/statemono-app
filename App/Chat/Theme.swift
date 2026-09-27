import SwiftUI

/// Telegram's night theme, measured from a 2x screenshot of Saved Messages on macOS.
enum Theme {
    static let background = Color(hex: 0x12181F)
    /// Outgoing bubbles share one gradient pinned to the window, #4B6DA7 at the top to #42639C at the bottom,
    /// so a bubble's color depends on where it sits. The bottom is the top darkened by ~10/255 per channel.
    static let bubbleTop = Color(hex: 0x4B6DA7)
    static let bubbleBottomBrightness = -0.04
    /// Header, composer, and day pills: a dark tint over a blur, with a hairline border.
    static let chromeFill = Color(hex: 0x1B232D).opacity(0.85)
    static let chromeBorder = Color.white.opacity(0.11)
    static let menuFill = Color(hex: 0x1F242B)
    static let searchFieldFill = Color(hex: 0x4C678F).opacity(0.1)
    static let searchHighlight = Color.white.opacity(0.3)
    static let tag = Color(hex: 0x5AAEFF)
    static let secondaryText = Color(hex: 0xC3D1E3)
    static let avatarTop = Color(hex: 0xACE1FB)
    static let avatarBottom = Color(hex: 0x74B4F6)
    static let accent = Color(hex: 0x5AA3F0)
}

enum Metrics {
    static let chromeHeight: CGFloat = 36
    static let chromeSpacing: CGFloat = 9
    static let sideMargin: CGFloat = 10
    static let headerTop: CGFloat = 6
    static let composerBottom: CGFloat = 8

    static let bubbleRadius: CGFloat = 16
    static let groupedRadius: CGFloat = 6
    /// Room reserved on the trailing side of every bubble for the tail, drawn or not.
    static let tailWidth: CGFloat = 6
    static let bubbleTrailing: CGFloat = 11
    static let textMaxWidth: CGFloat = 400
    static let previewWidth: CGFloat = 282
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// The floating-glass look shared by the header and composer pieces.
    func chromeBackground<S: InsettableShape>(_ shape: S) -> some View {
        background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Theme.chromeFill)
                shape.strokeBorder(Theme.chromeBorder, lineWidth: 0.5)
            }
        }
    }
}
