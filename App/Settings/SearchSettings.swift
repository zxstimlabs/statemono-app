import SwiftUI

/// Settings › Search: one row per tier of docs/search-plan.md, with a switch, what it does, and its status. Apple's
/// on-device AI comes first (owner, 2026-10-01): Smart Search runs on Apple's text model by default, with bge-small as a
/// more accurate download, and Apple Intelligence tags are on wherever Apple Intelligence runs.
struct SearchSettings: View {
    let smartSearch: SmartSearch
    let tags: AppleIntelligenceTags
    @State private var isConfirmingSmartSearchOff = false
    @State private var isConfirmingAppleModel = false
    @State private var isConfirmingTagsOff = false
    @State private var retagCount: Int?

    var body: some View {
        Form {
            Section {
                row("Basic search", status: "On. Finds links by the words in them and in their previews as you type, and allows for small typos.")
                smartSearchRow
                if smartSearch.isOn {
                    row("More accurate Smart Search", status: accurateStatus) {
                        Toggle("More accurate Smart Search", isOn: Binding(
                            get: { smartSearch.isAccurate },
                            set: { isOn in
                                if isOn { smartSearch.setAccurate(true) } else { isConfirmingAppleModel = true }
                            }
                        ))
                    }
                }
                tagsRow
                row("Storage", status: storage)
            } footer: {
                // A Mac form sets footers trailing and in body text otherwise.
                Text("Everything runs on this device. Smart Search uses Apple's on-device text model, or, more accurate, BAAI's bge-small-en-v1.5, downloaded from Hugging Face. Tags come from Apple Intelligence. Turning a step off deletes what it made here, the downloaded model included; Apple's models belong to the system and stay.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .settingsPage("Search")
        .alert("Turn Off Smart Search?", isPresented: $isConfirmingSmartSearchOff) {
            Button("Turn Off", role: .destructive) { smartSearch.turnOff() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(smartSearch.isAccurate
                ? "This deletes what Smart Search made for your links and the more accurate model (\(Self.bytes(smartSearch.modelBytes + smartSearch.vectorBytes))). Turning it back on makes them again."
                : "This deletes what Smart Search made for your links (\(Self.bytes(smartSearch.vectorBytes))). Turning it back on makes it again.")
        }
        .alert("Use Apple's Model Again?", isPresented: $isConfirmingAppleModel) {
            Button("Use Apple's Model", role: .destructive) { smartSearch.setAccurate(false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the more accurate model (\(Self.bytes(smartSearch.modelBytes))). Smart Search goes back to Apple's model and prepares your links again.")
        }
        .alert("Turn Off Tags?", isPresented: $isConfirmingTagsOff) {
            Button("Turn Off", role: .destructive) { tags.turnOff() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the tags made for your links (\(Self.bytes(tags.storageBytes))). Turning them back on tags every link again.")
        }
        .alert("Re-tag All Links?", isPresented: Binding(get: { retagCount != nil }, set: { if !$0 { retagCount = nil } })) {
            Button("Re-tag All") { tags.retagAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apple Intelligence tags ^[\(retagCount ?? 0) link](inflect: true) again, one at a time, while Statemono is open. Each keeps its tags until new ones arrive.")
        }
    }

    // MARK: - Smart Search

    private var smartSearchRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Smart Search", status: smartSearchStatus) {
                Toggle("Smart Search", isOn: Binding(
                    get: { smartSearch.isOn },
                    set: { isOn in
                        if isOn { smartSearch.turnOn() } else { isConfirmingSmartSearchOff = true }
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
            "Finds links by meaning, even without the same words, with Apple's on-device text model."
        case .gettingAppleModel:
            "Getting Apple's text model ready…"
        case .downloading(let progress):
            "Downloading the more accurate model… \(progress.formatted(.percent.precision(.fractionLength(0))))"
        case .preparing(let progress):
            "Preparing your links… \(progress.ready.formatted()) of \(progress.total.formatted())"
        case .paused(let progress):
            "Paused in Low Power Mode. \(progress.ready.formatted()) of \(progress.total.formatted()) links ready."
        case .ready(let count):
            smartSearch.isAccurate
                ? "On, with bge-small. ^[\(count) link](inflect: true) ready."
                : "On, with Apple's model. ^[\(count) link](inflect: true) ready."
        case .failed(.appleModel):
            "Apple's text model isn't available right now. Check your connection and try again."
        case .failed(.download):
            "Couldn't download the more accurate model. Check your connection and try again."
        }
    }

    private var accurateStatus: LocalizedStringKey {
        smartSearch.isAccurate
            ? "On. Uses BAAI's bge-small instead of Apple's model."
            : "Uses BAAI's bge-small instead of Apple's model, which finds more by meaning. Downloads \(Self.bytes(SmartSearch.model.downloadSize)) once."
    }

    // MARK: - Tags

    private var tagsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Apple Intelligence tags", status: tagsStatus) {
                Toggle("Apple Intelligence tags", isOn: Binding(
                    get: { tags.isOn && tags.availability.isAvailable },
                    set: { isOn in
                        if isOn { tags.turnOn() } else { isConfirmingTagsOff = true }
                    }
                ))
                .disabled(!tags.availability.isAvailable)
            }
            switch tags.state {
            case .tagging(let progress), .retagging(let progress):
                ProgressView(value: Double(progress.tagged), total: Double(max(progress.total, 1)))
            case .ready:
                Button("Re-tag All Links…") {
                    Task { retagCount = await tags.taggableCount() }
                }
            default:
                EmptyView()
            }
        }
    }

    private var tagsStatus: LocalizedStringKey {
        guard tags.availability.isAvailable else { return tags.availability.explanation }
        switch tags.state {
        case .off, .unavailable:
            return tags.availability.explanation
        case .tagging(let progress):
            return "Tagging your links… \(progress.tagged.formatted()) of \(progress.total.formatted())"
        case .retagging(let progress):
            return "Re-tagging your links… \(progress.tagged.formatted()) of \(progress.total.formatted())"
        case .paused(let progress):
            return "Paused in Low Power Mode. \(progress.tagged.formatted()) of \(progress.total.formatted()) links tagged."
        case .waiting(let progress):
            return "Waiting for Apple Intelligence, which didn't respond. It tries again when you come back to Statemono. \(progress.tagged.formatted()) of \(progress.total.formatted()) links tagged."
        case .ready(let count):
            return "On. ^[\(count) link](inflect: true) tagged."
        }
    }

    // MARK: - Storage

    private var storage: LocalizedStringKey {
        let (model, vectors, tagBytes) = (smartSearch.modelBytes, smartSearch.vectorBytes, tags.storageBytes)
        guard model + vectors + tagBytes > 0 else { return "Smart Search and tags haven't stored anything yet." }
        if model > 0 {
            return "Smart Search uses \(Self.bytes(model + vectors)): \(Self.bytes(model)) for its model and \(Self.bytes(vectors)) for your links. Tags use \(Self.bytes(tagBytes))."
        }
        return "Smart Search uses \(Self.bytes(vectors)) for your links. Tags use \(Self.bytes(tagBytes))."
    }

    private static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }

    private func row(_ title: LocalizedStringKey, status: LocalizedStringKey, note: LocalizedStringKey? = nil) -> some View {
        SettingsRow(title: title, status: status, note: note) { EmptyView() }
    }

    private func row(
        _ title: LocalizedStringKey,
        status: LocalizedStringKey,
        note: LocalizedStringKey? = nil,
        @ViewBuilder control: () -> some View
    ) -> some View {
        SettingsRow(title: title, status: status, note: note, control: control)
    }
}
