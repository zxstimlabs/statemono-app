import Foundation
import Observation
import StatemonoKit

/// Smart Search (docs/search-plan.md, Phase 3): finds links by meaning, even without the same words. Turning it on
/// downloads the search model, bge-small (`SearchModel.bgeSmall`, 133 MB), once. Then, while the app is open, it makes a
/// vector for every link, and one for each new link after that, pausing in Low Power Mode. A search adds the links
/// closest in meaning that keyword search missed (`related(to:excluding:)`). Everything runs on the device.
///
/// It's per device, like the other search settings: the switch is kept in `UserDefaults`, and vectors never sync.
@MainActor @Observable
final class SmartSearch {
    enum State: Equatable {
        case off
        /// The share of the download done.
        case downloading(Double)
        case preparing(VectorProgress)
        /// Waiting for Low Power Mode to end.
        case paused(VectorProgress)
        /// On, with this many links searchable.
        case ready(Int)
        /// The model couldn't be downloaded or loaded.
        case failed
    }

    static let model = SearchModel.bgeSmall
    /// How many related links a search adds after the keyword matches: Phase 0's choice.
    static let relatedCount = 3

    private(set) var state: State = .off
    /// What Smart Search keeps on this device: the model's files and the vectors, in bytes.
    private(set) var modelBytes: Int64 = 0
    private(set) var vectorBytes: Int64 = 0

    var isOn: Bool { state != .off }

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let store: SearchModelStore
    @ObservationIgnored private var embedder: BertEmbedder?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    /// Links changed while vectors were being made, so another pass follows.
    @ObservationIgnored private var needsAnotherPass = false
    /// Bumped by every start and stop, so work from before is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observation: FeedObservation?
    @ObservationIgnored private var powerObserver: (any NSObjectProtocol)?

    private static let enabledKey = "smartSearch.enabled"

    init(database: AppDatabase, store: SearchModelStore = SearchModelStore(model: SmartSearch.model)) {
        self.database = database
        self.store = store
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.linksChanged() }
        }
        if UserDefaults.standard.bool(forKey: Self.enabledKey) {
            start()
        } else {
            updateStorage()
        }
    }

    func turnOn() {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        start()
    }

    func retry() {
        start()
    }

    /// Stops the work, then deletes the model's files and every vector.
    func turnOff() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        generation += 1
        let running = [startTask, prepareTask].compactMap { $0 }
        running.forEach { $0.cancel() }
        startTask = nil
        prepareTask = nil
        observation?.cancel()
        observation = nil
        embedder = nil
        state = .off
        let (database, store) = (database, store)
        Task {
            // A batch being saved finishes first, so nothing is left behind.
            for task in running { await task.value }
            try? await database.removeAllVectors()
            try? store.remove()
            updateStorage()
        }
    }

    /// The links closest in meaning to `query`, best first, leaving out `excluded` (the keyword matches). Empty until the
    /// model is loaded. Links still waiting for a vector can't be found yet.
    func related(to query: String, excluding excluded: Set<UUID>) async -> [UUID] {
        guard let embedder else { return [] }
        let vector = await Task.detached(priority: .userInitiated) { embedder.vector(for: query, role: .query) }.value
        return (try? await database.relatedItems(to: vector, model: embedder.modelID, excluding: excluded, count: Self.relatedCount)) ?? []
    }

    // MARK: - Private

    /// Downloads the model if it's missing, loads it, then makes the vectors that are missing.
    private func start() {
        generation += 1
        startTask?.cancel()
        prepareTask?.cancel()
        prepareTask = nil
        let store = store
        startTask = Task {
            do {
                if !store.isInstalled {
                    state = .downloading(0)
                    try await store.install { progress in
                        Task { @MainActor [weak self] in
                            if case .downloading = self?.state { self?.state = .downloading(progress) }
                        }
                    }
                }
                embedder = try await Task.detached(priority: .userInitiated) { try store.load() }.value
            } catch {
                guard !Task.isCancelled else { return }
                // Damaged files are deleted, so trying again downloads them afresh.
                if store.isInstalled { try? store.remove() }
                state = .failed
                updateStorage()
                return
            }
            guard !Task.isCancelled else { return }
            updateStorage()
            observation = database.observeSearchContent { [weak self] in self?.linksChanged() }
            linksChanged()
        }
    }

    /// Links were added, edited, deleted or given a preview, or Low Power Mode changed: vectors may be missing.
    private func linksChanged() {
        guard embedder != nil else { return }
        if prepareTask != nil {
            needsAnotherPass = true
        } else {
            let generation = generation
            prepareTask = Task { await prepare(generation) }
        }
    }

    /// Makes vectors a batch at a time, newest links first, until none are missing.
    private func prepare(_ generation: Int) async {
        defer {
            if generation == self.generation { prepareTask = nil }
        }
        guard let embedder else { return }
        repeat {
            needsAnotherPass = false
            while !Task.isCancelled {
                guard let (work, progress) = try? await database.vectorWork(model: embedder.modelID),
                      !Task.isCancelled, generation == self.generation
                else { return }
                if work.isEmpty {
                    state = .ready(progress.total)
                    break
                }
                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    state = .paused(progress)
                    return
                }
                state = .preparing(progress)
                let batch = Array(work.prefix(16))
                let vectors = await Task.detached(priority: .utility) {
                    batch.map { (work: $0, vector: embedder.vector(for: $0.text, role: .document)) }
                }.value
                guard !Task.isCancelled else { return }
                do {
                    try await database.saveVectors(vectors, model: embedder.modelID)
                } catch {
                    return
                }
                updateStorage()
            }
        } while needsAnotherPass && !Task.isCancelled
    }

    private func updateStorage() {
        let (database, store) = (database, store)
        Task {
            let model = await Task.detached(priority: .utility) { store.sizeOnDisk }.value
            modelBytes = model
            vectorBytes = (try? await database.vectorStorageSize()) ?? 0
        }
    }
}
