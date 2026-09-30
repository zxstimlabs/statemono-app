import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Settings, a sheet over the chat on both platforms, opened by the header's gear (and ⌘, on the Mac). For now it
/// holds the search section of docs/search-plan.md: one row per tier, with a switch, what it does, and its status.
/// Apple Intelligence tags come in a later phase, so its switch stays off until then; the row already reports whether
/// this device could use Apple Intelligence.
struct SettingsView: View {
    let smartSearch: SmartSearch
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var appleIntelligence = AppleIntelligenceStatus.current
    @State private var isConfirmingTurnOff = false

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
                smartSearchRow
                row("Apple Intelligence tags", status: appleIntelligence.status, note: appleIntelligence.isAvailable ? Self.laterBuild : nil) {
                    Toggle("Apple Intelligence tags", isOn: .constant(false)).disabled(true)
                }
                row("Storage", status: storage)
            } header: {
                Text("Search")
            } footer: {
                // A Mac form sets footers trailing and in body text otherwise.
                Text("Everything runs on this device. Smart Search's model is BAAI's bge-small-en-v1.5, downloaded from Hugging Face. Turning a step off deletes what it made here, Smart Search's model included. Apple Intelligence's model belongs to the system and stays.")
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
        .alert("Turn Off Smart Search?", isPresented: $isConfirmingTurnOff) {
            Button("Turn Off", role: .destructive) { smartSearch.turnOff() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the search model and what Smart Search made for your links (\(Self.bytes(smartSearch.modelBytes + smartSearch.vectorBytes))). Turning it back on downloads the model again.")
        }
    }

    // MARK: - Smart Search

    private var smartSearchRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Smart Search", status: smartSearchStatus) {
                Toggle("Smart Search", isOn: Binding(
                    get: { smartSearch.isOn },
                    set: { isOn in
                        if isOn { smartSearch.turnOn() } else { isConfirmingTurnOff = true }
                    }
                ))
            }
            switch smartSearch.state {
            case .downloading(let progress):
                ProgressView(value: progress)
            case .preparing(let progress):
                ProgressView(value: Double(progress.ready), total: Double(max(progress.total, 1)))
            case .failed:
                Button("Try Again") { smartSearch.retry() }
            default:
                EmptyView()
            }
        }
    }

    private var smartSearchStatus: LocalizedStringKey {
        switch smartSearch.state {
        case .off:
            "Finds links by meaning, even without the same words. Downloads a search model once (\(Self.bytes(SmartSearch.model.downloadSize)))."
        case .downloading(let progress):
            "Downloading the search model… \(progress.formatted(.percent.precision(.fractionLength(0))))"
        case .preparing(let progress):
            "Preparing your links… \(progress.ready.formatted()) of \(progress.total.formatted())"
        case .paused(let progress):
            "Paused in Low Power Mode. \(progress.ready.formatted()) of \(progress.total.formatted()) links ready."
        case .ready(let count):
            count == 1 ? "On. 1 link ready." : "On. \(count.formatted()) links ready."
        case .failed:
            "Couldn't download the search model. Check your connection and try again."
        }
    }

    private var storage: LocalizedStringKey {
        let (model, vectors) = (smartSearch.modelBytes, smartSearch.vectorBytes)
        guard model + vectors > 0 else { return "Smart Search and tags haven't stored anything yet." }
        return "Smart Search uses \(Self.bytes(model + vectors)): \(Self.bytes(model)) for its model and \(Self.bytes(vectors)) for your links."
    }

    private static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
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
