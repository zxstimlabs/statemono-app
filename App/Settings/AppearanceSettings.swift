import SwiftUI

/// Light or dark, chosen in Settings › Appearance and kept per device. System follows the device, which is what both
/// Telegram apps do by default. Light is Telegram's Day theme and Dark its Night (`Theme`).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// The `UserDefaults` key, read with `@AppStorage`.
    static let key = "appearance"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    #if os(macOS)
    /// For `NSApp.appearance`: nil follows the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
    #else
    /// For a window's `overrideUserInterfaceStyle`: unspecified follows the system.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
    #endif
}

extension View {
    /// Applies Settings › Appearance to the window, and with it to everything `Theme` draws and to sheets. Not
    /// `preferredColorScheme`: on iOS 18, going back to the system's appearance (nil) left an open sheet in the old one.
    /// The window's own override (on the Mac, the app's appearance) reaches the sheet as the system passes it down.
    func appAppearance(_ appearance: AppAppearance) -> some View {
        #if os(macOS)
        onChange(of: appearance, initial: true) {
            NSApp.appearance = appearance.nsAppearance
        }
        #else
        background { WindowStyle(style: appearance.interfaceStyle) }
        #endif
    }
}

#if os(iOS)
/// Sets its window's `overrideUserInterfaceStyle`.
private struct WindowStyle: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> StyleView {
        StyleView()
    }

    func updateUIView(_ view: StyleView, context: Context) {
        view.style = style
    }

    final class StyleView: UIView {
        var style = UIUserInterfaceStyle.unspecified {
            didSet { window?.overrideUserInterfaceStyle = style }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.overrideUserInterfaceStyle = style
        }
    }
}
#endif

/// Settings › Appearance: the choice between System, Light and Dark, as a native inline picker (checkmarks on iPhone,
/// radio buttons on the Mac).
struct AppearanceSettings: View {
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                // A Mac form sets footers trailing and in body text otherwise.
                Text(Self.footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .settingsPage("Appearance")
    }

    #if os(macOS)
    private static let footer: LocalizedStringKey = "System matches the appearance set in System Settings on this Mac."
    #else
    private static let footer: LocalizedStringKey = "System matches the appearance set in Settings on this iPhone."
    #endif
}
