import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Settings, a sheet over the chat on both platforms, opened by the header's gear (and ⌘, on the Mac). For now it
/// holds the search section of docs/search-plan.md: one row per tier, with a switch, what it does, and its status.
/// Smart Search and Apple Intelligence tags come in later phases, so their switches stay off until then; the tags row
/// already reports whether this device could use Apple Intelligence.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var appleIntelligence = AppleIntelligenceStatus.current

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Text("Settings")
                .font(.headline)
                .padding(.top, 16)
            form
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 520)
        #else
        NavigationStack {
            form
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var form: some View {
        Form {
            Section {
                row("Basic search", status: "On. Finds links by the words in them and in their previews as you type, and allows for small typos.")
                row("Smart Search", status: "Finds links by meaning, even without the same words. Downloads a language model from Apple.", note: Self.laterBuild) {
                    Toggle("Smart Search", isOn: .constant(false)).disabled(true)
                }
                row("Apple Intelligence tags", status: appleIntelligence.status, note: appleIntelligence.isAvailable ? Self.laterBuild : nil) {
                    Toggle("Apple Intelligence tags", isOn: .constant(false)).disabled(true)
                }
                row("Storage", status: "Smart Search and tags haven't stored anything yet.")
            } header: {
                Text("Search")
            } footer: {
                // A Mac form sets footers trailing and in body text otherwise.
                Text("Everything runs on this device. Turning a step off deletes what it made here. Apple's model files stay: the system manages them, and apps can't remove them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        // The user may turn Apple Intelligence on in the system's Settings and come back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appleIntelligence = .current }
        }
    }

    private static let laterBuild: LocalizedStringKey = "Arrives in a later build."

    private func row(_ title: LocalizedStringKey, status: LocalizedStringKey, note: LocalizedStringKey? = nil) -> some View {
        row(title, status: status, note: note) { EmptyView() }
    }

    private func row(
        _ title: LocalizedStringKey,
        status: LocalizedStringKey,
        note: LocalizedStringKey? = nil,
        @ViewBuilder control: () -> some View
    ) -> some View {
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
            control().labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

/// Whether this device can run Apple Intelligence, in the words the tags row uses. FoundationModels exists from
/// iOS/macOS 26; before that, the answer is an OS update.
enum AppleIntelligenceStatus: Equatable {
    case needsUpdate
    case deviceNotEligible
    case turnedOff
    case notReady
    case available
    case unavailable

    static var current: AppleIntelligenceStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.deviceNotEligible): return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled): return .turnedOff
            case .unavailable(.modelNotReady): return .notReady
            case .unavailable: return .unavailable
            }
        }
        #endif
        return .needsUpdate
    }

    var isAvailable: Bool { self == .available }

    var status: LocalizedStringKey {
        switch self {
        case .available: "Uses Apple Intelligence to add keywords to each link, so searches find related words."
        #if os(macOS)
        case .needsUpdate: "Needs macOS 26 or later."
        case .deviceNotEligible: "This Mac doesn't support Apple Intelligence."
        #else
        case .needsUpdate: "Needs iOS 26 or later."
        case .deviceNotEligible: "This iPhone doesn't support Apple Intelligence."
        #endif
        case .turnedOff: "Turn on Apple Intelligence in Settings to use this."
        case .notReady: "Apple Intelligence is still getting ready. Try again later."
        case .unavailable: "Apple Intelligence isn't available on this device."
        }
    }
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
