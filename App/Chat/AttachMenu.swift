import SwiftUI

enum AttachMenuItem: CaseIterable, Identifiable {
    case photoOrVideo, giftPremium, wallet, file, camera, audio, location, article

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .photoOrVideo: "Photo Or Video"
        case .giftPremium: "Gift Premium"
        case .wallet: "Wallet"
        case .file: "File"
        case .camera: "Camera"
        case .audio: "Audio"
        case .location: "Location"
        case .article: "Article"
        }
    }

    var systemImage: String {
        switch self {
        case .photoOrVideo: "photo"
        case .giftPremium: "gift"
        case .wallet: "wallet.bifold"
        case .file: "doc"
        case .camera: "camera"
        case .audio: "music.note"
        case .location: "mappin.and.ellipse"
        case .article: "text.alignleft"
        }
    }
}

/// Telegram's attach popup: an opaque panel that opens over the paperclip button.
struct AttachMenu: View {
    var onSelect: (AttachMenuItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AttachMenuItem.allCases) { item in
                AttachMenuRow(item: item) { onSelect(item) }
            }
        }
        .padding(.vertical, 4)
        .fixedSize()
        .background(Theme.menuFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
    }
}

private struct AttachMenuRow: View {
    let item: AttachMenuItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .frame(height: 28)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08))
                }
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressFeedback)
        .onHover { isHovered = $0 }
    }
}
