import SwiftUI

struct Composer: View {
    @Binding var text: String
    var onAttach: () -> Void
    var onSend: () -> Void
    @FocusState private var isFocused: Bool

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
                .focused($isFocused)
                .onSubmit(onSend)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: Metrics.chromeHeight)
                .chromeBackground(RoundedRectangle(cornerRadius: Metrics.chromeHeight / 2))

            circleButton(action: canSend ? onSend : {}) {
                if canSend {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accent)
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 19))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, Metrics.sideMargin)
        .padding(.bottom, Metrics.composerBottom)
        .onAppear { isFocused = true }
    }

    private func circleButton(action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .frame(width: Metrics.chromeHeight, height: Metrics.chromeHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .chromeBackground(Circle())
    }
}
