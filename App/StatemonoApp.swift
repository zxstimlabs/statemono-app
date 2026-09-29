import SwiftUI

@main
struct StatemonoApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 776)
        .windowResizability(.contentMinSize)
        .commands { SettingsCommands() }
        #endif
    }
}
