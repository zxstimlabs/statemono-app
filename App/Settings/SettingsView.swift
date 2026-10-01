import SwiftUI

/// Settings, a sheet over the chat on both platforms, opened by the header's gear (and ⌘, on the Mac). Its first page
/// lists the sections, each opening its own page, like Telegram's settings and the system's: iCloud on its own at the
/// top, as the system puts the account, then Appearance and Search.
struct SettingsView: View {
    let smartSearch: SmartSearch
    let sync: ICloudSync
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            pages
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 520)
        #else
        pages
            // Inside a pushed page, `dismiss` would only go back a page.
            .environment(\.closeSettings) { dismiss() }
        #endif
    }

    private var pages: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ICloudSettings(sync: sync)
                    } label: {
                        LabeledContent {
                            Text(sync.summary)
                        } label: {
                            SettingsLabel("iCloud", systemImage: "icloud.fill", color: Color(hex: 0x0079FF))
                        }
                    }
                }
                Section {
                    NavigationLink {
                        AppearanceSettings()
                    } label: {
                        LabeledContent {
                            Text(appearance.title)
                        } label: {
                            SettingsLabel("Appearance", systemImage: "circle.lefthalf.filled", color: Color(hex: 0x32ADE6))
                        }
                    }
                    NavigationLink {
                        SearchSettings(smartSearch: smartSearch)
                    } label: {
                        SettingsLabel("Search", systemImage: "magnifyingglass", color: Color(hex: 0x8E8E93))
                    }
                }
            }
            .formStyle(.grouped)
            .settingsPage("Settings")
        }
    }
}

/// A section's row title with its icon: a white symbol on a colored rounded square, like the rows in Telegram-iOS's
/// settings (`renderSettingsIcon`: 30pt, corner radius 8) and the system's. The Mac's rows are smaller.
private struct SettingsLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color

    init(_ title: LocalizedStringKey, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    #if os(macOS)
    private static let (side, radius, glyph): (CGFloat, CGFloat, CGFloat) = (20, 5, 11)
    #else
    private static let (side, radius, glyph): (CGFloat, CGFloat, CGFloat) = (30, 8, 16)
    #endif

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: Self.glyph, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.side, height: Self.side)
                .background(color, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        }
    }
}

/// A row with a title, a status line under it, an optional note, and a control such as a switch on its trailing side.
struct SettingsRow<Control: View>: View {
    let title: LocalizedStringKey
    let status: LocalizedStringKey
    var note: LocalizedStringKey?
    let control: Control

    init(title: LocalizedStringKey, status: LocalizedStringKey, note: LocalizedStringKey? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.status = status
        self.note = note
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control.labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

extension View {
    /// A Settings page's title, and on iPhone the Done button that closes the sheet from any page. The Mac's Done
    /// button sits under the pages instead.
    func settingsPage(_ title: LocalizedStringKey) -> some View {
        modifier(SettingsPage(title: title))
    }
}

private struct SettingsPage: ViewModifier {
    let title: LocalizedStringKey
    @Environment(\.closeSettings) private var closeSettings

    func body(content: Content) -> some View {
        #if os(macOS)
        content.navigationTitle(title)
        #else
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: closeSettings)
                }
            }
        #endif
    }
}

extension EnvironmentValues {
    /// Closes the Settings sheet from any of its pages.
    @Entry var closeSettings: () -> Void = {}
}

extension FocusedValues {
    /// Opens the Settings sheet of the chat in front, for ⌘, and the app menu.
    @Entry var openSettings: (() -> Void)?
}

#if os(macOS)
/// The app menu's Settings… item. Settings is a sheet over the chat, as on iPhone, rather than the Mac's own Settings
/// window, so the item opens that sheet.
struct SettingsCommands: Commands {
    @FocusedValue(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openSettings?() }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(openSettings == nil)
        }
    }
}
#endif
