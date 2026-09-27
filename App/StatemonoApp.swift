import SwiftUI

@main
struct StatemonoApp: App {
    @State private var store = ChatStore(messages: SampleMessages.make())

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(store)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 776)
        .windowResizability(.contentMinSize)
        #endif
    }
}
