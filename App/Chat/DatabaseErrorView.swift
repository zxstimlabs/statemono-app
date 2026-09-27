import StatemonoKit
import SwiftUI

/// Opens the database at launch. If that fails, the app explains and offers to try again or start a new database,
/// instead of crashing.
@MainActor @Observable
final class Library {
    enum State {
        case ready(ChatStore)
        case failed(LibraryError)
    }

    private(set) var state: State
    /// Where an unreadable database was moved by `startOver()`, to tell the user once.
    var movedAside: URL?

    private let location: DatabaseLocation

    init(location: DatabaseLocation = .default) {
        self.location = location
        state = Self.open(location)
    }

    func retry() {
        state = Self.open(location)
    }

    /// Moves the current database aside (kept, not deleted) and starts a new, empty one.
    func startOver() {
        do {
            movedAside = try AppDatabase.moveAside(location)
            state = Self.open(location)
        } catch {
            state = .failed(LibraryError(error, location: location))
        }
    }

    private static func open(_ location: DatabaseLocation) -> State {
        do {
            let database = try AppDatabase.open(at: location)
            PreviewImageLoader.shared.attach(database)
            return .ready(ChatStore(database: database, previews: LinkPreviewFetcher()))
        } catch {
            return .failed(LibraryError(error, location: location))
        }
    }
}

struct LibraryError {
    /// The underlying error, as SQLite reported it, for the details text.
    let details: String
    let folder: URL

    init(_ error: any Error, location: DatabaseLocation) {
        details = String(describing: error)
        folder = location.directory
    }
}

/// The chat when the database is open, or why it isn't.
struct RootView: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        Group {
            switch library.state {
            case .ready(let store):
                ChatView().environment(store)
            case .failed(let error):
                DatabaseErrorView(error: error, onRetry: library.retry, onStartOver: library.startOver)
            }
        }
        .alert("Started a new database", isPresented: Binding(get: { library.movedAside != nil }, set: { if !$0 { library.movedAside = nil } })) {
            #if os(macOS)
            Button("Show in Finder") {
                if let url = library.movedAside { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                library.movedAside = nil
            }
            #endif
            Button("OK", role: .cancel) { library.movedAside = nil }
        } message: {
            Text("The old database was kept as \(library.movedAside?.lastPathComponent ?? "a backup"), next to the new one, so its links can still be recovered.")
        }
    }
}

struct DatabaseErrorView: View {
    let error: LibraryError
    let onRetry: () -> Void
    let onStartOver: () -> Void

    @State private var confirmsStartOver = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.secondaryText)
                .padding(.bottom, 4)
            Text("Statemono couldn't open its database")
                .font(.system(size: 17, weight: .semibold))
            Text("Your saved links are still on disk. Try again, or start a new database: the current one is kept aside, not deleted.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Text(error.details)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.secondaryText.opacity(0.8))
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 420)
                .background(Theme.chromeFill, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 10) {
                Button("Start with a New Database…") { confirmsStartOver = true }
                    .buttonStyle(.bordered)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 6)
            #if os(macOS)
            Button("Show Database in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([error.folder])
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
            #endif
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .confirmationDialog("Start with a new database?", isPresented: $confirmsStartOver) {
            Button("Start Over", role: .destructive, action: onStartOver)
        } message: {
            Text("Statemono will start empty. The current database is renamed and kept in the same folder, so its links can still be recovered.")
        }
    }
}
