import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    /// Menus: TelegramSwift's night palette tints the blur with its background (#18222D) at 70%, and draws the hover
    /// highlight and separators in its grayIcon (#B1C3D5) at 15% and 10%.
    static let menuTint = Color(hex: 0x18222D).opacity(0.7)
    static let menuHighlight = Color(hex: 0xB1C3D5).opacity(0.15)
    static let menuSeparator = Color(hex: 0xB1C3D5).opacity(0.1)
    /// Telegram's redUI. A screenshot shows it as #DE6560, in the display's color space rather than sRGB.
    static let destructive = Color(hex: 0xEF5B5B)
    static let searchFieldFill = Color(hex: 0x4C678F).opacity(0.1)
    static let searchHighlight = Color.white.opacity(0.3)
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
    /// How far a text field's glass grows above and below it while the field has focus: 36pt becomes 42pt.
    static let focusGrowth: CGFloat = 3
    /// The glass growing into focus, or back.
    static let focusAnimation = Animation.smooth(duration: 0.25)

    static let bubbleRadius: CGFloat = 16
    static let groupedRadius: CGFloat = 6
    /// Room reserved on the trailing side of every bubble for the tail, drawn or not.
    static let tailWidth: CGFloat = 6
    /// From a bubble's tail room to the row's trailing edge. Telegram-iOS's bubble ends 10pt from the edge: its frame
    /// sits 3pt in, and the drawn bubble stops 7pt inside the frame, before the tail.
    #if os(macOS)
    static let bubbleTrailing: CGFloat = 11
    #else
    static let bubbleTrailing: CGFloat = 10 - tailWidth
    #endif
    /// The Mac's widest bubble content: text, or a link preview. On iOS only the row limits it (`bubbleLeadingSpace`).
    static let textMaxWidth: CGFloat = 400
    static let previewWidth: CGFloat = 282
    static let menuRadius: CGFloat = 18

    /// The least room a bubble leaves on its leading side in a row `rowWidth` wide.
    static func bubbleLeadingSpace(rowWidth: CGFloat) -> CGFloat {
        #if os(macOS)
        56
        #else
        // Telegram-iOS (`ChatMessageItemWidthFill`, `ChatMessageBubbleItemNode`) gives a bubble the row less 36pt when
        // the row is up to 500pt wide, and 85% of it past that, 65% once the chat is wider than 680pt. Telegram checks
        // 680 against the whole width, safe areas included; on every iPhone the row lands on the same side of it.
        // Of that, the bubble's frame gets all but 9pt, 3pt from the trailing edge, and the drawn bubble starts 1pt
        // inside the frame. On a phone held upright, bubbles reach 43pt from the left edge.
        let fill = rowWidth <= 500 ? rowWidth - 36 : floor(rowWidth * (rowWidth > 680 ? 0.65 : 0.85))
        return rowWidth - fill + 7
        #endif
    }
}

/// Text sizes in the chat. The Mac keeps the sizes measured from Telegram for macOS. On iOS they follow Telegram-iOS
/// (`ChatPresentationData`, `ChatMessageDateAndStatusNode`, `ChatMessageDateHeader`): the system Text Size picks a
/// base size, 17pt by default, and the rest are fractions of it.
struct ChatTextSize: Equatable {
    /// Messages, the composer, and the search field.
    var message: CGFloat = 13
    /// Link preview text and the search result counter.
    var preview: CGFloat = 12
    /// A bubble's time and read checks.
    var time: CGFloat = 11
    /// Day separators.
    var day: CGFloat = 12

    static let mac = ChatTextSize()
}

extension ChatTextSize {
    /// Telegram-iOS's sizes for a base size.
    init(base: CGFloat) {
        message = base
        preview = floor(base * 14 / 17)
        time = floor(base * 11 / 17)
        day = min(18, floor(base * 13 / 17))
    }

    #if os(iOS)
    /// Telegram-iOS's "Use System Text Size": the system's body size, snapped to the nearest of Telegram's sizes.
    init(_ dynamicTypeSize: DynamicTypeSize) {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits).pointSize
        let steps: [CGFloat] = [14, 15, 16, 17, 19, 23, 26]
        self.init(base: steps.min { abs($0 - body) < abs($1 - body) } ?? 17)
    }
    #endif
}

extension EnvironmentValues {
    @Entry var chatTextSize = ChatTextSize.mac
    /// The width of the feed's rows. On iOS, a link preview's image is decoded to fit the bubble it allows.
    @Entry var feedWidth: CGFloat = 0
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
    /// The floating-glass look shared by the header and composer pieces. `outset` draws the glass that much beyond
    /// the view's top and bottom edges without changing its layout.
    func chromeBackground<S: InsettableShape>(_ shape: S, outset: CGFloat = 0) -> some View {
        background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Theme.chromeFill)
                shape.strokeBorder(Theme.chromeBorder, lineWidth: 0.5)
            }
            .padding(.vertical, -outset)
        }
    }
}
