import SwiftUI

struct Composer: View {
    @Binding var text: String
    var onSend: () -> Void
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Metrics.chromeSpacing) {
            circleButton(action: {}) {
                Image(systemName: "paperclip")
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
            }

            HStack(alignment: .bottom, spacing: 0) {
                TextField("", text: $text, prompt: Text("Write a message...").foregroundStyle(Theme.secondaryText), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1...10)
                    .focused($isFocused)
                    .onSubmit(onSend)
                    .padding(.leading, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: Metrics.chromeHeight)
                ChromeIconButton(systemImage: "gift", size: 18, color: Theme.secondaryText) {}
                    .frame(width: 36, height: Metrics.chromeHeight)
                Button {} label: {
                    StickerIcon()
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 36, height: Metrics.chromeHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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
