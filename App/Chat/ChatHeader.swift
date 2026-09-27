import SwiftUI

struct ChatHeader: View {
    /// Room on the leading side for the window's traffic lights.
    var leadingInset: CGFloat
    var onSearch: () -> Void

    var body: some View {
        HStack(spacing: Metrics.chromeSpacing) {
            HStack(spacing: 8) {
                SavedMessagesAvatar()
                    .frame(width: 29, height: 29)
                Text("Saved Messages")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.leading, 3.5)
            .frame(height: Metrics.chromeHeight)
            .chromeBackground(Capsule())
            .contentShape(Capsule())
            #if os(macOS)
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
            #endif

            HStack(spacing: 0) {
                ChromeIconButton(systemImage: "magnifyingglass", size: 17, action: onSearch)
                    .keyboardShortcut("f", modifiers: .command)
                ChromeIconButton(systemImage: "ellipsis", size: 15, weight: .bold) {}
            }
            .frame(width: 78, height: Metrics.chromeHeight)
            .chromeBackground(Capsule())
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, Metrics.sideMargin)
        .padding(.top, Metrics.headerTop)
    }
}

struct SavedMessagesAvatar: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.avatarTop, Theme.avatarBottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: "bookmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
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
        .buttonStyle(.plain)
    }
}
