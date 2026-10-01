import SwiftUI

/// Settings › iCloud: the sync switch and what sync is doing (docs/sync-plan.md).
struct ICloudSettings: View {
    let sync: ICloudSync

    var body: some View {
        Form {
            Section {
                SettingsRow(title: "Sync with iCloud", status: sync.statusText) {
                    Toggle("Sync with iCloud", isOn: Binding(get: { sync.isOn }, set: { sync.setOn($0) }))
                        .disabled(!sync.isAvailable)
                }
            } footer: {
                // A Mac form sets footers trailing and in body text otherwise.
                Text(Self.footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .settingsPage("iCloud")
    }

    private static let footer: LocalizedStringKey = "Your messages sync through your private iCloud, with their text and links end-to-end encrypted, so Apple can't read them. Link previews don't sync: each device loads its own. Turning sync off keeps everything, on this \(ICloudSync.device) and in iCloud."
}

extension ICloudSync {
    #if os(macOS)
    static let device = "Mac"
    #else
    static let device = "iPhone"
    #endif

    /// The status in a word or two, beside the iCloud row on Settings' first page.
    var summary: LocalizedStringKey {
        guard isAvailable else { return "Unavailable" }
        guard isOn else { return "Off" }
        switch account {
        case .checking: return ""
        case .available: return problem == .quotaExceeded ? "Storage Full" : "On"
        case .noAccount: return "Not Signed In"
        default: return "Unavailable"
        }
    }

    /// The status in a sentence, under the switch.
    var statusText: LocalizedStringKey {
        guard isAvailable else { return "This build can't use iCloud." }
        guard isOn else {
            return problem == .deletedInICloud
                ? "Statemono's data was deleted from iCloud, so syncing stopped. Turn it on to upload the messages on this \(Self.device) again."
                : "Off. Your messages stay on this \(Self.device)."
        }
        switch account {
        case .checking:
            return "Checking iCloud…"
        case .noAccount:
            #if os(macOS)
            return "Sign in to iCloud in System Settings to sync."
            #else
            return "Sign in to iCloud in Settings to sync."
            #endif
        case .restricted:
            return "iCloud is restricted on this \(Self.device)."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Syncing starts when it's back."
        case .unknown:
            return "Couldn't reach iCloud. Syncing starts when it can."
        case .available:
            break
        }
        if problem == .quotaExceeded {
            return "Your iCloud storage is full. ^[\(pendingCount) message](inflect: true) waiting to sync."
        }
        if isSyncing {
            return pendingCount > 0 ? "Syncing ^[\(pendingCount) message](inflect: true)…" : "Syncing…"
        }
        if pendingCount > 0 {
            return "^[\(pendingCount) message](inflect: true) waiting to sync."
        }
        if let lastSynced {
            return "Up to date. Last synced \(lastSynced, format: .relative(presentation: .named))."
        }
        return "Up to date."
    }
}
