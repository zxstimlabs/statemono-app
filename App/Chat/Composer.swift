import SwiftUI

struct Composer: View {
    @Binding var text: String
    var focus: FocusState<ChatFocus?>.Binding
    var onAttach: () -> Void
    var onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Metrics.chromeSpacing) {
            circleButton(action: onAttach) {
                Image(systemName: "paperclip")
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
            }

            TextField("", text: $text, prompt: Text("Write a message...").foregroundStyle(Theme.secondaryText), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(1...10)
                .focused(focus, equals: .composer)
                .onSubmit(onSend)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: Metrics.chromeHeight)
                .chromeBackground(RoundedRectangle(cornerRadius: Metrics.chromeHeight / 2))

            circleButton(action: canSend ? onSend : {}) {
                // One symbol that morphs between mic and send, rather than two views that swap.
                Image(systemName: canSend ? "paperplane.fill" : "mic")
                    .font(.system(size: canSend ? 16 : 19))
                    .foregroundStyle(canSend ? Theme.accent : .white)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.smooth(duration: 0.2), value: canSend)
            }
        }
        .padding(.horizontal, Metrics.sideMargin)
        .padding(.bottom, Metrics.composerBottom)
        .onAppear { focus.wrappedValue = .composer }
    }

    private func circleButton(action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .frame(width: Metrics.chromeHeight, height: Metrics.chromeHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.pressFeedback)
        .chromeBackground(Circle())
    }
}
