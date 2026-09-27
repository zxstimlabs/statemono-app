import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What a message's context menu offers: TelegramSwift's items for your own message in Saved Messages
/// (`chatMenuItems`). Only Copy Text and Delete do anything yet.
enum MessageMenuItem: CaseIterable, Identifiable {
    case reply, translate, copyText, edit, pin, forward, select, delete

    var id: Self { self }

    /// Telegram's groups, in its order, with a separator between each.
    static let groups: [[MessageMenuItem]] = [[.reply], [.translate, .copyText], [.edit, .pin, .forward, .select], [.delete]]

    var title: String {
        switch self {
        case .reply: String(localized: "Reply")
        case .translate: String(localized: "Translate")
        case .copyText: String(localized: "Copy Text")
        case .edit: String(localized: "Edit")
        case .pin: String(localized: "Pin")
        case .forward: String(localized: "Forward")
        case .select: String(localized: "Select")
        case .delete: String(localized: "Delete")
        }
    }

    var systemImage: String {
        switch self {
        case .reply: "arrowshape.turn.up.left"
        case .translate: "translate"
        case .copyText: "doc.on.doc"
        case .edit: "square.and.pencil"
        case .pin: "pin"
        case .forward: "arrowshape.turn.up.right"
        case .select: "checkmark.circle"
        case .delete: "trash"
        }
    }

    var isDestructive: Bool { self == .delete }

    /// In Telegram, Forward opens a submenu of recent chats.
    var hasSubmenu: Bool { self == .forward }

    /// Telegram runs these with ⌘ and the key while the menu is open. The shortcut isn't shown.
    var keyEquivalent: String? {
        switch self {
        case .reply: "r"
        case .copyText: "c"
        case .edit: "e"
        default: nil
        }
    }
}

/// A message's context menu, drawn like Telegram's.
struct MessageMenu: View {
    var highlighted: MessageMenuItem?
    var onHover: (MessageMenuItem, Bool) -> Void
    var onSelect: (MessageMenuItem) -> Void

    var body: some View {
        MenuPanel {
            ForEach(MessageMenuItem.groups.indices, id: \.self) { index in
                if index > 0 {
                    MenuSeparator()
                }
                ForEach(MessageMenuItem.groups[index]) { item in
                    MenuRow(
                        title: item.title,
                        systemImage: item.systemImage,
                        isDestructive: item.isDestructive,
                        hasSubmenu: item.hasSubmenu,
                        isHighlighted: highlighted == item
                    ) { isHovered in
                        onHover(item, isHovered)
                    } action: {
                        onSelect(item)
                    }
                }
            }
        }
    }
}

#if os(macOS)
/// The open context menu: whose it is, where it opened, and which item is highlighted. It works through the events
/// `ChatView` hands it while it's open, as TelegramSwift's `AppMenu` takes the keyboard, the scroll wheel and clicks
/// from its window.
@MainActor @Observable
final class MessageMenuState {
    enum Command {
        case select(MessageMenuItem)
        case close
    }

    let messageID: Message.ID
    /// Where the pointer was, in the chat view's coordinates.
    let point: CGPoint
    private(set) var highlighted: MessageMenuItem?
    @ObservationIgnored private var hovered: MessageMenuItem?
    @ObservationIgnored private var typed = ""
    @ObservationIgnored private var typedAt = Date.distantPast

    private static let items = MessageMenuItem.groups.flatMap(\.self)

    init(messageID: Message.ID, point: CGPoint) {
        self.messageID = messageID
        self.point = point
    }

    func hover(_ item: MessageMenuItem, _ isHovered: Bool) {
        if isHovered {
            hovered = item
            highlighted = item
        } else if hovered == item {
            hovered = nil
            if highlighted == item { highlighted = nil }
        }
    }

    /// What an event does to the menu. Left clicks are the rows' and the backdrop's to handle.
    func handle(_ event: NSEvent) -> Command? {
        switch event.type {
        case .rightMouseDown:
            // A right-click on an item chooses it, as in Telegram. Anywhere else it closes the menu.
            hovered.map(Command.select) ?? .close
        case .keyDown:
            handleKey(event)
        default:
            nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Command? {
        switch event.specialKey {
        case .downArrow:
            move(by: 1)
            return nil
        case .upArrow:
            move(by: -1)
            return nil
        case .carriageReturn, .enter:
            return highlighted.map(Command.select)
        default:
            break
        }
        if event.keyCode == 53 { return .close } // Escape
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) {
            return Self.items.first { $0.keyEquivalent == characters }.map(Command.select)
        }
        // Typing selects the first item whose title starts with what's been typed. A 0.3s pause starts over.
        guard !characters.isEmpty, characters.allSatisfy({ $0.isLetter || $0 == " " }) else { return nil }
        typed = Date.now.timeIntervalSince(typedAt) < 0.3 ? typed + characters : characters
        typedAt = .now
        if let item = Self.items.first(where: { $0.title.lowercased().hasPrefix(typed) }) {
            highlighted = item
        }
        return nil
    }

    private func move(by step: Int) {
        guard let index = highlighted.flatMap(Self.items.firstIndex(of:)) else {
            highlighted = step > 0 ? Self.items.first : Self.items.last
            return
        }
        highlighted = Self.items[min(max(index + step, 0), Self.items.count - 1)]
    }
}

/// Shows the open context menu at the pointer, over a backdrop that catches clicks outside it. It grows out of the
/// pointer, as Telegram's does.
struct MessageMenuOverlay: View {
    let menu: MessageMenuState
    let onSelect: (MessageMenuItem) -> Void
    let onClose: () -> Void

    @State private var isGrown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                MenuPlacement(point: menu.point) {
                    MessageMenu(highlighted: menu.highlighted, onHover: menu.hover, onSelect: onSelect)
                }
                // Telegram scales the menu up from 0.1 around the pointer. Scaling the whole placement around the
                // pointer does that wherever the menu ended up relative to it.
                .scaleEffect(isGrown || reduceMotion ? 1 : 0.1, anchor: UnitPoint(
                    x: menu.point.x / max(proxy.size.width, 1),
                    y: menu.point.y / max(proxy.size.height, 1)
                ))
            }
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.2)) { isGrown = true }
        }
    }
}
#endif

enum Pasteboard {
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}
