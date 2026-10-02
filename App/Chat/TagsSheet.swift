import StatemonoKit
import SwiftUI

/// A message's Apple Intelligence tags (docs/search-plan.md, Showing tags), opened from its menu: the tags, or "Not
/// tagged yet", and a Re-tag button that asks the model again. Tags can't be edited by hand. Choosing one closes the
/// sheet and searches for it.
struct TagsSheet: View {
    let messageID: Message.ID
    let tags: AppleIntelligenceTags
    var onSearch: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var itemTags: ItemTags?
    @State private var isRetagging = false
    @State private var retagFailed = false

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            content
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 380, height: 480)
        #else
        content
            .presentationDetents([.medium, .large])
        #endif
    }

    private var content: some View {
        NavigationStack {
            Form {
                Section {
                    if let itemTags {
                        if itemTags.tags.isEmpty {
                            Text(itemTags.attemptedAt == nil ? "Not tagged yet" : "Apple Intelligence found no tags for this link.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(itemTags.tags, id: \.self) { tag in
                                Button {
                                    onSearch(tag)
                                } label: {
                                    Label(tag, systemImage: "tag")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Searches for this tag")
                            }
                        }
                    }
                } footer: {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Section {
                    Button(action: retag) {
                        HStack {
                            Text("Re-tag")
                            Spacer()
                            if isRetagging { ProgressView().controlSize(.small) }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(isRetagging || !tags.availability.isAvailable)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Tags")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
        .task { itemTags = await tags.tags(for: messageID) }
    }

    private var footer: LocalizedStringKey {
        if retagFailed {
            return itemTags?.tags.isEmpty == false
                ? "Apple Intelligence couldn't tag this link again. It keeps the tags it had."
                : "Apple Intelligence couldn't tag this link. Try again later."
        }
        guard tags.availability.isAvailable else { return tags.availability.explanation }
        #if os(macOS)
        return "Made by Apple Intelligence on this Mac, so searches find related words. Click a tag to search for it."
        #else
        return "Made by Apple Intelligence on this iPhone, so searches find related words. Tap a tag to search for it."
        #endif
    }

    private func retag() {
        isRetagging = true
        retagFailed = false
        Task {
            retagFailed = !(await tags.retag(messageID))
            itemTags = await tags.tags(for: messageID)
            isRetagging = false
        }
    }
}
