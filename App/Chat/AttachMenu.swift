import SwiftUI

enum AttachMenuItem: CaseIterable, Identifiable {
    case photoOrVideo, giftPremium, wallet, file, camera, audio, location, article

    var id: Self { self }

    var title: String {
        switch self {
        case .photoOrVideo: String(localized: "Photo Or Video")
        case .giftPremium: String(localized: "Gift Premium")
        case .wallet: String(localized: "Wallet")
        case .file: String(localized: "File")
        case .camera: String(localized: "Camera")
        case .audio: String(localized: "Audio")
        case .location: String(localized: "Location")
        case .article: String(localized: "Article")
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

/// Telegram's attach popup, a menu that opens over the paperclip button.
struct AttachMenu: View {
    var onSelect: (AttachMenuItem) -> Void
    @State private var hovered: AttachMenuItem?

    var body: some View {
        MenuPanel {
            ForEach(AttachMenuItem.allCases) { item in
                MenuRow(title: item.title, systemImage: item.systemImage, isHighlighted: hovered == item) { isHovered in
                    if isHovered { hovered = item } else if hovered == item { hovered = nil }
                } action: {
                    onSelect(item)
                }
            }
        }
    }
}
