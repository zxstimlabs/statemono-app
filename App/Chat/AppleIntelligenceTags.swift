import Foundation
import Observation
import StatemonoKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Apple Intelligence tags (docs/search-plan.md, Phase 4): 3–8 keywords per link from the system's on-device model, so
/// keyword search finds related words. On by default wherever Apple Intelligence runs (owner, 2026-10-01), and per
/// device: tags are made here and never synced. While the app is open it tags links one at a time, newest first, once
/// their previews are in; Low Power Mode pauses it. Each link is tagged once; Re-tag All and a link's Re-tag button ask
/// again.
@MainActor @Observable
final class AppleIntelligenceTags {
    enum State: Equatable {
        case off
        /// On, but Apple Intelligence can't run here now; `availability` says why.
        case unavailable
        case tagging(TagProgress)
        case retagging(TagProgress)
        /// Waiting for Low Power Mode to end.
        case paused(TagProgress)
        /// Apple Intelligence didn't answer, for a reason that may pass. Tagging picks up on the next change, or when
        /// the app comes back to the front.
        case waiting(TagProgress)
        /// On, with this many links tried.
        case ready(Int)
    }

    private(set) var isOn: Bool
    private(set) var availability = AppleIntelligenceStatus.current
    private(set) var state: State = .off
    private(set) var storageBytes: Int64 = 0

    /// A message's menu offers its tags while tags are on and can be made.
    var showsMenuItem: Bool { isOn && availability.isAvailable }

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false
    /// Bumped by every start and stop, so work from before is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observation: FeedObservation?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    private static let enabledKey = "tags.enabled"
    /// When Re-tag All started; links last tried before it are tagged again, across relaunches, until none are left.
    private static let retagSinceKey = "tags.retagAllSince"
    private static let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    init(database: AppDatabase) {
        self.database = database
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        isOn = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.linksChanged() }
        })
        // Apple Intelligence may have been turned on, or finished downloading, while the app was away.
        observers.append(center.addObserver(forName: Self.didBecomeActive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAvailability() }
        })
        if isOn { start() }
        updateStorage()
    }

    func turnOn() {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        isOn = true
        start()
    }

    /// Stops tagging and deletes every tag. Apple Intelligence's model stays: the system manages it.
    func turnOff() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        UserDefaults.standard.removeObject(forKey: Self.retagSinceKey)
        isOn = false
        stop()
        state = .off
        let (database, running) = (database, workTask)
        Task {
            await running?.value
            try? await database.removeAllTags()
            updateStorage()
        }
    }

    /// Tags every link again, one at a time, while the app is open. Each keeps its old tags until new ones arrive.
    func retagAll() {
        UserDefaults.standard.set(Date.now, forKey: Self.retagSinceKey)
        linksChanged()
    }

    /// How many links Re-tag All would cover.
    func taggableCount() async -> Int {
        (try? await database.tagWork(retagSince: nil, limit: 0).progress.total) ?? 0
    }

    /// Asks the model again for one link, ahead of any other tagging. False if it couldn't tag it; the old tags stay.
    func retag(_ id: UUID) async -> Bool {
        guard availability.isAvailable, let work = try? await database.tagWork(for: id) else { return false }
        guard case .tags(let tags) = await Self.makeTags(for: work.text) else { return false }
        try? await database.saveTags(tags, for: id, osVersion: Self.osVersion)
        updateStorage()
        return true
    }

    func tags(for id: UUID) async -> ItemTags? {
        try? await database.tags(for: id)
    }

    // MARK: - Private

    #if os(macOS)
    private static let didBecomeActive = NSApplication.didBecomeActiveNotification
    #else
    private static let didBecomeActive = UIApplication.didBecomeActiveNotification
    #endif

    private var retagSince: Date? {
        UserDefaults.standard.object(forKey: Self.retagSinceKey) as? Date
    }

    /// Also picks up tagging that stopped because the app went away.
    private func refreshAvailability() {
        let wasAvailable = availability.isAvailable
        availability = .current
        guard isOn else { return }
        if availability.isAvailable != wasAvailable {
            start()
        } else {
            linksChanged()
        }
    }

    private func start() {
        stop()
        guard availability.isAvailable else {
            state = .unavailable
            return
        }
        observation = database.observeSearchContent { [weak self] in self?.linksChanged() }
        linksChanged()
    }

    private func stop() {
        generation += 1
        workTask?.cancel()
        workTask = nil
        observation?.cancel()
        observation = nil
    }

    /// Links were added, deleted or given a preview, Low Power Mode changed, or Re-tag All began: tags may be due.
    private func linksChanged() {
        guard isOn, availability.isAvailable else { return }
        if workTask != nil {
            needsAnotherPass = true
        } else {
            let generation = generation
            workTask = Task { await work(generation) }
        }
    }

    /// Tags one link at a time, newest first, until none are waiting.
    private func work(_ generation: Int) async {
        defer {
            if generation == self.generation { workTask = nil }
        }
        repeat {
            needsAnotherPass = false
            while !Task.isCancelled, generation == self.generation {
                let since = retagSince
                guard let (work, progress) = try? await database.tagWork(retagSince: since, limit: 1),
                      !Task.isCancelled, generation == self.generation
                else { return }
                guard let link = work.first else {
                    if since != nil { UserDefaults.standard.removeObject(forKey: Self.retagSinceKey) }
                    state = .ready(progress.total)
                    break
                }
                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    state = .paused(progress)
                    return
                }
                state = since == nil ? .tagging(progress) : .retagging(progress)
                let result = await Self.makeTags(for: link.text)
                guard !Task.isCancelled, generation == self.generation else { return }
                switch result {
                case .tags(let tags):
                    try? await database.saveTags(tags, for: link.id, osVersion: Self.osVersion)
                case .refused:
                    // The model won't tag this link. It's marked tried, so it isn't asked again in a loop.
                    try? await database.saveTags(nil, for: link.id, osVersion: Self.osVersion)
                case .failed:
                    // Not the link's fault (the app went to the background, the model was busy): stop here, and pick up
                    // on the next change or when the app comes back.
                    state = .waiting(progress)
                    return
                }
                updateStorage()
            }
        } while needsAnotherPass && !Task.isCancelled
    }

    private func updateStorage() {
        let database = database
        Task { storageBytes = (try? await database.tagStorageSize()) ?? 0 }
    }

    enum TaggingResult {
        case tags([String])
        /// The model declined this link, or can't handle its text.
        case refused
        /// Something else went wrong; trying again later may work.
        case failed
    }

    private static func makeTags(for text: String) async -> TaggingResult {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            do {
                let tags = try await LinkTagger.tags(for: text)
                return tags.isEmpty ? .refused : .tags(tags)
            } catch {
                return LinkTagger.isAboutTheLink(error) ? .refused : .failed
            }
        }
        #endif
        return .failed
    }
}

#if canImport(FoundationModels)
@available(iOS 26, macOS 26, *)
@Generable
struct LinkTags {
    @Guide(description: "Short lowercase keywords for what the link is about, without # symbols", .count(3...8))
    var tags: [String]
}

/// Asks Apple Intelligence's content-tagging model for a link's tags, the way Phase 0 measured them
/// (`Tools/SearchEval`, `Tagger`).
@available(iOS 26, macOS 26, *)
enum LinkTagger {
    /// Tags exist so keyword search finds related words, so they ask for topics beyond the page's own words. Without
    /// "in English", Phase 0 got German and Spanish tags for about a dozen English pages.
    static let instructions = """
        Tag a saved web link so it can be found by searching later. Give 3 to 8 short lowercase keywords: what it is \
        about, its broader topics, and related words someone might search for that aren't in the text. Write every tag in \
        English, whatever the language of the text.
        """

    /// The model's context is small, and a link's title, site and description fit well within this.
    private static let maxCharacters = 2_000

    static func tags(for text: String) async throws -> [String] {
        let session = LanguageModelSession(model: SystemLanguageModel(useCase: .contentTagging), instructions: instructions)
        let response = try await session.respond(to: String(text.prefix(maxCharacters)), generating: LinkTags.self)
        var seen = Set<String>()
        return response.content.tags
            .map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines)) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Whether the model turned down this link's text, rather than failing for a reason that might pass.
    static func isAboutTheLink(_ error: any Error) -> Bool {
        if #available(iOS 27, macOS 27, *), let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal, .contextSizeExceeded, .unsupportedLanguageOrLocale, .unsupportedTranscriptContent:
                return true
            default:
                return false
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal, .exceededContextWindowSize, .unsupportedLanguageOrLocale, .decodingFailure:
                return true
            default:
                return false
            }
        }
        return false
    }
}
#endif

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
            switch SystemLanguageModel(useCase: .contentTagging).availability {
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

    /// Why tags can't be made here, for Settings and the Tags sheet.
    var explanation: LocalizedStringKey {
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
