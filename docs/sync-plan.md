# Sync plan: iCloud with CKSyncEngine

Status: built and tested on 2026-10-01 (see Built). The owner settled the open questions the same day. The owner deployed the schema to Production the same day. Build 19 crashed at launch on iPhone (see Built); build 20 fixed it.

The owner chose CloudKit for Apple devices on 2026-10-01. Other devices (a Linux desktop) come later, and CLAUDE.md rules out running CloudKit and a server side by side, so that choice is for later.

## The idea

- **The database on the device stays the source of truth.** The UI still reads only from SQLite. Sync is a background job that uploads what changed here and applies what changed elsewhere.
- **Apple's `CKSyncEngine`** (iOS 17 / macOS 14, inside our iOS 18 / macOS 15 minimum) does the scheduling, push notifications, retries, and account monitoring. The app supplies the records and decides what a change means.
- **The user's private iCloud database.** No server, no sign-in screen, nothing for us to host. The data counts against the user's iCloud storage, at a few KB per link.
- **One `SyncBackend` protocol** in StatemonoKit, per the design principles. `CloudKitSync` is the first implementation; a server could replace it later.

## What syncs

- **Only what the user made:** each item's `id`, `text`, `link`, `createdAt`, `updatedAt` and `deletedAt`.
- **Not synced, rebuilt on each device:** link previews, their images and placeholders (`media`, `MediaStore`), and Smart Search vectors. This follows the existing rule that each device fetches previews itself, so saving a preview never touches `updatedAt` or `isDirty`.
  - A link that arrives from another device gets its preview fetched here, the way `ChatStore` retries links missing a preview at launch.
- **Settings stay per device:** appearance and Smart Search.

## How it works

### Records

- **One custom zone,** `Items`. `CKSyncEngine` needs a custom zone to track changes.
- **One record per item:** type `Item`, record name = the item's UUID. The integer rowid never leaves the device, as now.
- **Fields:** `createdAt`, `updatedAt` and `deletedAt` as dates, plus `text` and `link`.
- **End-to-end encrypted text (owner, 2026-10-01):** `text` and `link` go in the record's `encryptedValues`. They're encrypted with keys in the user's iCloud Keychain, so Apple can't read them. We never query the server, so nothing needs to be searchable there.
- **Record metadata:** CloudKit's system fields (`encodeSystemFields`) are kept per item, so each upload builds on the server's last version and doesn't conflict with itself.

### Uploading

- **What's pending** is what `isDirty` already marks: new links, deletes, later edits.
  - At start, the app adds every dirty item to the engine's pending changes.
  - After that, it adds them as they're written. The same database observation catches the share extension's rows, which a Darwin notification announces (step 4).
- **Batches:** the engine asks for the next batch (`nextRecordZoneChangeBatch`). It's built with `RecordZoneChangeBatch(pendingChanges:recordProvider:)`, which stops at CloudKit's request limit.
- **After a save,** `isDirty` is cleared and the new system fields are stored. If `updatedAt` changed while the request was out, the item stays dirty and goes again.

### Downloading

- **New or changed records** are applied by UUID:
  - A new item gets a new local rowid.
  - An existing one takes the remote values if its `updatedAt` is newer.
  - Applied changes leave `isDirty` false. The FTS triggers and the feed observation see them like any write.
- **Deletes** travel as `deletedAt`, never as a CloudKit record deletion, so tombstones mean the same thing on every device and on a future server.
- **Push:** the engine subscribes to the private database and fetches when a silent push arrives. The app also asks it to fetch when it comes to the front, since the simulator doesn't always get pushes.

### Conflicts

- **Last write wins** by `updatedAt`, for the whole item, as the design principles say. Only deletes, and later edits, change an item after it's made, so conflicts are rare.
- **When the server's copy changed** (`serverRecordChanged`), the newer `updatedAt` wins. If the server's is newer, it's applied here. If ours is, it's re-sent on top of the server's record.

### Accounts and resets

- **Signed out, or iCloud off for the app (owner, 2026-10-01):** syncing stops and every message stays on the device. Local-first and tombstones mean we never delete the user's data. Apple's sample deletes local data here; we won't.
- **Signed in again, or a different account (owner, 2026-10-01):** everything on the device is uploaded to that account, merging with what's there. The catch: links from the old account join the new one.
- **The zone deleted in iCloud:**
  - **The user deleted the app's data** in iCloud's settings (reason `purged`), seen by a device that had synced: everything stays on the device, and syncing turns itself off until the user turns it on again.
  - **Any other deletion,** such as a reset of their encrypted data (`encryptedDataReset`), or one from before this device first synced: the zone is created again and everything on the device is uploaded. A device's first fetch hears about old deletions too; in testing, that turned a new device's sync off until this rule was fixed.
- **iCloud storage full** (`quotaExceeded`): items stay dirty, and Settings says so.

## Settings › iCloud

A third row on the Settings sheet's first page, next to Appearance and Search, in the same native grouped style. Its value shows the status.

- **Sync with iCloud:** a switch, on by default (owner, 2026-10-01). Turning it off stops syncing and leaves everything in iCloud and on the device.
- **Status line:**
  - "Up to date"
  - "Syncing 34 links…"
  - "Sign in to iCloud in Settings to sync"
  - "iCloud storage is full"
  - "Waiting for a connection"
- **The footer** says what syncs (your messages) and what doesn't (previews, which each device loads itself), and that message text is end-to-end encrypted.

## Database changes

- **`syncState`:** one row holding `CKSyncEngine.State.Serialization`, saved on every `stateUpdate` event. The engine needs it to resume.
- **`itemSync`:** `itemRowID` (primary key, references `item`) and `systemFields` (blob). It's kept apart from `item` so CloudKit's details stay out of the model, and a server backend could use its own table.
- **No change to `item`.** Its UUID, `updatedAt`, `deletedAt` and `isDirty` already carry everything sync needs.
- **The share extension** (step 4) moves the database into the App Group. The sync tables move with it. The extension never runs the engine; it only writes dirty rows.

## Code

- **StatemonoKit `Sync/`:**
  - `SyncBackend`: start, stop, status, local changes.
  - `CloudKitSync`: the `CKSyncEngine` delegate, and record ↔ item mapping.
  - `SyncStatus`.
  - The merge rules are plain functions on `AppDatabase` (apply a remote item, mark one uploaded), so tests can run them without CloudKit.
- **App:** `ChatStore` owns the sync and starts it with the database. `App/Settings/ICloudSettings.swift` is the new page.
- **Project** (`project.yml`):
  - **Both apps:** the iCloud container `iCloud.com.statemono` (the comment in `project.yml` already reserves the name), CloudKit, and push (`aps-environment`; `com.apple.developer.aps-environment` on the Mac).
  - **iOS:** a new `Config/Statemono-iOS.entitlements`, and the `remote-notification` background mode.

## Owner steps

Xcode's automatic signing (`-allowProvisioningUpdates`) may register these itself. If it can't, these are the developer portal steps (Certificates, Identifiers & Profiles):

| Where | Field | Value |
|---|---|---|
| Identifiers › iCloud Containers › + | Description | Statemono |
| | Identifier | `iCloud.com.statemono` |
| Identifiers › App IDs › `com.statemono` | iCloud | On, CloudKit, container `iCloud.com.statemono` |
| | Push Notifications | On |

Before the first TestFlight build with sync: in the CloudKit Console (icloud.developer.apple.com), deploy the schema from Development to Production. Debug builds use the Development environment, which creates the schema as records are first saved. TestFlight and App Store builds use Production, which has no schema until it's deployed.

## Testing

- **Unit tests** (StatemonoKit, in-memory database), for the merge rules:
  - A new remote item.
  - Newer and older remote edits.
  - A remote delete.
  - A local edit while an upload was out.
  - Re-uploading everything after a reset.
- **Live, two devices on one Apple ID:** this Mac and the iPhone simulator. The owner signs the simulator into iCloud. Both builds are signed with the team, because CloudKit needs the entitlements.
  - **Data:** it all goes to the Development environment, so test data never mixes with Production.
  - **The Mac:** it uploads the owner's existing local database. The alternative is a scratch copy with another bundle ID that shares the container.
  - **Checks:**
    - A new link appears on the other device.
    - A delete reaches the other device.
    - Changes made offline arrive after reconnecting.
    - Both sides changing the same item.
    - Signing out keeps everything.
    - The first upload of a few thousand links, and how long it takes.
- **Then TestFlight,** after the schema is deployed to Production.

## Phases

1. **Plumbing:** entitlements, container, the engine starting with saved state, and the Settings page showing account status.
2. **Items:** uploading, downloading, conflicts, tombstones, and previews for incoming links. Unit tests and the two-device test.
3. **Edges:** account changes, zone resets, a full iCloud, and the status details.
4. **Release:** the owner deploys the schema to Production, then TestFlight.

## Decisions (owner, 2026-10-01)

1. **On by default,** with the switch in Settings › iCloud, like Apple Notes.
2. **Signing out or switching accounts:** keep everything on the device, and upload it to whichever account signs in next, merging with what's there.
3. **Text and link are end-to-end encrypted** (`encryptedValues`).

## Built (2026-10-01)

- **StatemonoKit `Sync/`:** `AppDatabase+Sync` (the merge rules) and `CloudKitSync` (the `CKSyncEngine` delegate), plus migration `v3 sync` (`itemSync`, `syncState`). `SyncBackend` is the protocol a server could implement later, with `SyncEvent` for the status. The merge rules on `AppDatabase` are shared.
- **App:**
  - `ICloudSync` (`App/Chat/ICloudSync.swift`) runs the engine, feeds it dirty items, fetches when the app comes to the front, and keeps the status.
  - `ICloudSettings` is the page, and Settings' first page has an iCloud section.
  - `SettingsRow` is now shared with the Search page.
- **Rules beyond the plan:**
  - An item that comes back from the server as the very same version is marked clean. This happens after re-uploading everything without record metadata.
  - When the feed's window would grow by more than a page at once, other than by loading history, it goes back to the newest page. Synced messages can arrive by the thousand inside the window, and the feed isn't lazy.
- **Signing:**
  - This Mac is registered on the team, so signed Mac builds work (`-allowProvisioningUpdates -allowProvisioningDeviceRegistration` the first time).
  - The first signed build created `iCloud.com.statemono` and turned on iCloud and push for `com.statemono`.
- **Unit tests** (`SyncTests`, 7): dirty until saved, an edit while a save was out, a new remote item, last write wins both ways, a changed link dropping its preview, and resets.
- **Live test** on this Mac, in the Development environment.
  - **Setup:** two copies of the app, both with the real bundle ID, unsandboxed, each given its own data folder with `STATEMONO_DATA_DIR` (debug builds only).
  - **Results:**
    - 90 links uploaded in about 15s and downloaded to an empty copy in about 9s, identical (IDs, text, dates).
    - A new message reached the other copy when it started.
    - Two deletes of one message, made a second apart on each side while both were closed, ended with the later one on both, nothing dirty.
    - 2,000 messages uploaded in 45s and downloaded in 33s.
    - A fresh copy re-uploading 90 links the server already had, while receiving 2,001, settled in 22s with nothing dirty, at 152MB. Before the window fix it was 364–473MB.
  - **Not tested here:**
    - Pushes. Two copies of one bundle ID share a push registration, so the other copy only fetched on start. TestFlight on two devices tests them.
    - Signing out of iCloud and a full iCloud.
    - The iPhone. This Xcode 27 install has no Simulator app, so no simulator could be signed into iCloud.
  - **Afterwards** the test zone was deleted from the Development environment, so a debug build of the real app doesn't download test data.
- **Scratch App IDs didn't work:** they got "Invalid bundle ID for container" (CKError 10) for over 15 minutes after automatic signing created them. The real `com.statemono` worked at once.
- **Build 19 crashed at launch on iPhone.**
  - **Cause:** the iOS archive was made unsigned, as CLAUDE.md's recipe said, so the App Store export had no iCloud or push entitlements. `CKContainer(identifier:)` traps when the app isn't entitled to the container. That's an `EXC_BREAKPOINT` in CloudKit, not a catchable exception. It reproduced in the simulator and on the Mac with unsigned builds. The Mac's build 19 was fine, because its archive is signed.
  - **Fix, in two parts:**
    - Sync now reads the app's own signed entitlements first (`Entitlements`, `CloudKitSync.canUse`) and stays off without them, so a misbuilt app runs without sync instead of crashing.
    - The iOS recipe signs the archived app ad hoc with its entitlements before export.
  - **Build 20:** both apps went to TestFlight on 2026-10-01, with the iOS export checked to carry the container, CloudKit, and production push.

