import Foundation
import Observation

/// In-memory stand-in for the feed until it reads from the GRDB database.
@MainActor @Observable
final class ChatStore {
    private(set) var messages: [Message]

    init(messages: [Message] = []) {
        self.messages = messages
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(Message(id: UUID(), text: text, date: .now))
    }
}
