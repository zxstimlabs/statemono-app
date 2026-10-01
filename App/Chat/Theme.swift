import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Telegram's colors, in two themes that follow the window's appearance (Settings › Appearance, `AppAppearance`).
/// Night was measured from a 2x screenshot of Saved Messages on macOS. Day is Telegram's "Day" theme, taken from
/// TelegramSwift's `whitePalette` and Telegram-iOS's `DefaultDayPresentationTheme`, not yet checked against a screenshot.
/// Inside a bubble everything stays white in both, as in Telegram's Day.
enum Theme {
    /// Day: Telegram's plain white `chatBackground`, the Day theme's default wallpaper on iOS too.
    static let background = Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x12181F))
    /// Text and icons over the chat and its glass. Day: black, as are Telegram-iOS's input panel controls.
    static let text = Color(light: .black, dark: .white)
    /// Outgoing bubbles share one gradient pinned to the window, #4B6DA7 at the top to #42639C at the bottom,
    /// so a bubble's color depends on where it sits. The bottom is the top darkened by ~10/255 per channel.
    /// Day: TelegramSwift's outgoing #4C91C7, shaded the same way.
    static let bubbleTop = Color(light: Color(hex: 0x4C91C7), dark: Color(hex: 0x4B6DA7))
    static let bubbleBottomBrightness = -0.04
    /// Header, composer, and day pills: a tint over a blur, with a hairline border. Day: Telegram-iOS's floating
    /// history buttons (`historyNavigation`), #F7F7F7 with a #C8C7CC border.
    static let chromeFill = Color(light: Color(hex: 0xF7F7F7).opacity(0.85), dark: Color(hex: 0x1B232D).opacity(0.85))
    static let chromeBorder = Color(light: Color(hex: 0xC8C7CC), dark: .white.opacity(0.11))
    /// The floating buttons' icons. Day: Telegram-iOS's `historyNavigation` foreground.
    static let floatingButtonIcon = Color(light: Color(hex: 0x88888D), dark: .white)
    /// Menus: TelegramSwift tints the blur with its background at 70%, and draws the hover highlight and separators in
    /// its grayIcon at 15% and 10%. Night: #18222D and #B1C3D5. Day: #FFFFFF and #9E9E9E.
    static let menuTint = Color(light: Color(hex: 0xFFFFFF).opacity(0.7), dark: Color(hex: 0x18222D).opacity(0.7))
    static let menuHighlight = Color(light: Color(hex: 0x9E9E9E).opacity(0.15), dark: Color(hex: 0xB1C3D5).opacity(0.15))
    static let menuSeparator = Color(light: Color(hex: 0x9E9E9E).opacity(0.1), dark: Color(hex: 0xB1C3D5).opacity(0.1))
    /// Telegram's redUI. A screenshot shows night's as #DE6560, in the display's color space rather than sRGB.
    static let destructive = Color(light: Color(hex: 0xFF3B30), dark: Color(hex: 0xEF5B5B))
    /// Day: Telegram-iOS's search field fill.
    static let searchFieldFill = Color(light: .black.opacity(0.06), dark: Color(hex: 0x4C678F).opacity(0.1))
    /// Behind search matches in bubbles, which are blue in both themes.
    static let searchHighlight = Color.white.opacity(0.3)
    /// Day: TelegramSwift's grayText.
    static let secondaryText = Color(light: Color(hex: 0x999999), dark: Color(hex: 0xC3D1E3))
    static let avatarTop = Color(hex: 0xACE1FB)
    static let avatarBottom = Color(hex: 0x74B4F6)
    static let accent = Color(light: Color(hex: 0x2481CC), dark: Color(hex: 0x5AA3F0))

    /// Search results on iPhone: Telegram-iOS's `chatList` message and date text and its separator. Night: #8D8E93,
    /// #545458 at 55%. Day: #8E8E93, #C8C7CC.
    static let searchListSecondaryText = Color(light: Color(hex: 0x8E8E93), dark: Color(hex: 0x8D8E93))
    static let searchListSeparator = Color(light: Color(hex: 0xC8C7CC), dark: Color(hex: 0x545458).opacity(0.55))
    /// The band behind a section title, a shade off the background.
    static let searchListHeaderFill = Color(light: .black.opacity(0.03), dark: .white.opacity(0.04))
    /// A pressed row. Day: Telegram-iOS's `chatList` highlight.
    static let searchListPressed = Color(light: Color(hex: 0xE5E5EA), dark: .white.opacity(0.06))
    /// Search results on the Mac: TelegramSwift's `grayText` for dates, `accentSelect` behind the current result, and
    /// `border` between rows.
    static let searchDropdownDate = Color(light: Color(hex: 0x999999), dark: Color(hex: 0xB1C3D5))
    static let searchDropdownSelected = Color(light: Color(hex: 0x4C91C7), dark: Color(hex: 0x3D6A97))
    static let searchDropdownSeparator = Color(light: Color(hex: 0xEAEAEA), dark: Color(hex: 0x213040))
    /// Behind matches in the dropdown's text. Day: TelegramSwift's text selection color (`selectTextBubble_incoming`).
    static let searchDropdownHighlight = Color(light: Color(hex: 0xCCDDEA), dark: .white.opacity(0.3))

    /// A message's menu on iPhone: Telegram-iOS's `contextMenu` colors. The panel fill is for iOS before 26,
    /// where Telegram has no glass.
    static let contextMenuDestructive = Color(light: Color(hex: 0xFF3B30), dark: Color(hex: 0xEB5545))
    static let contextMenuSeparator = Color(light: Color(hex: 0x3C3C43).opacity(0.2), dark: .white.opacity(0.15))
    static let contextMenuFill = Color(light: Color(hex: 0xF9F9F9).opacity(0.78), dark: Color(hex: 0x1C1C1C).opacity(0.85))
    static let contextMenuPressed = Color(light: Color(hex: 0x3C3C43).opacity(0.2), dark: .white.opacity(0.1))
    /// Over the blurred chat behind the menu.
    static let contextMenuDim = Color(light: Color(hex: 0x000A26).opacity(0.2), dark: .black.opacity(0.6))
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
        // inside the frame, so Telegram's bubbles reach 43pt from the left edge of an upright phone. The owner found
        // that too wide, so bubbles here leave `extraLeadingSpace` more: 84pt.
        let fill = rowWidth <= 500 ? rowWidth - 36 : floor(rowWidth * (rowWidth > 680 ? 0.65 : 0.85))
        return rowWidth - fill + 7 + extraLeadingSpace
        #endif
    }

    #if os(iOS)
    /// Room beyond Telegram-iOS's on a bubble's leading side.
    static let extraLeadingSpace: CGFloat = 41
    #endif
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

    /// `light` in light mode and `dark` in dark mode, resolved wherever the color is drawn.
    init(light: Color, dark: Color) {
        #if os(macOS)
        let (light, dark) = (NSColor(light), NSColor(dark))
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
        #else
        let (light, dark) = (UIColor(light), UIColor(dark))
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
        #endif
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
