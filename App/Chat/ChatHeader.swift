import SwiftUI

/// The avatar, the search field, and the ⋯ button. The search field opens the search panel below it.
struct ChatHeader: View {
    /// Room on the leading side for the window's traffic lights.
    var leadingInset: CGFloat
    @Bindable var search: ChatSearch
    var focus: FocusState<ChatFocus?>.Binding
    var onOpenSearch: () -> Void
    var onCloseSearch: () -> Void

    var body: some View {
        HStack(spacing: Metrics.chromeSpacing) {
            SavedMessagesAvatar()
                .frame(width: Metrics.chromeHeight, height: Metrics.chromeHeight)
            SearchField(search: search, focus: focus, onOpen: onOpenSearch, onClose: onCloseSearch)
            ChromeIconButton(systemImage: "ellipsis", size: 15, weight: .bold) {}
                .frame(width: Metrics.chromeHeight, height: Metrics.chromeHeight)
                .chromeBackground(Circle())
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, Metrics.sideMargin)
        .padding(.top, Metrics.headerTop)
        #if os(macOS)
        // The window has no title bar, so the header strip (the avatar and the gaps around the controls) moves it.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        }
        #endif
    }
}

struct SavedMessagesAvatar: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.avatarTop, Theme.avatarBottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: "bookmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .allowsHitTesting(false)
    }
}

/// Dims a button the instant it's pressed and brings it back smoothly on release. Feedback belongs on the press,
/// not the click that follows it.
struct PressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .animation(configuration.isPressed ? nil : .smooth(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressFeedbackStyle {
    static var pressFeedback: PressFeedbackStyle { PressFeedbackStyle() }
}

struct ChromeIconButton: View {
    let systemImage: String
    var size: CGFloat
    var weight: Font.Weight = .regular
    var color: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressFeedback)
    }
}
