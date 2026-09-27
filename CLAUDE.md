# Statemono

Telegram "Saved Messages" for links: share or paste a link, it shows up as a chat bubble with a rich preview, and everything is full-text searchable. SwiftUI, one codebase for iPhone and Mac. See README.md for setup and layout.

## Design principles
- Local-first: SQLite (GRDB) on the device is the source of truth. The UI reads only from the local database.
- Share extensions stay tiny: they write the row to the shared App Group database and do nothing else (no metadata fetch).
- Deletes are tombstones (`deletedAt`), never hard deletes.
- All sync goes through one `SyncBackend` protocol so the backend can be swapped.
- Items: client-generated UUID `id`, integer rowid for FTS, `updatedAt` for last-write-wins, a dirty flag for pending uploads.

## Status
- The macOS chat UI was built before the database (plan step 2 ahead of step 1). It runs on an in-memory `ChatStore` seeded from `App/SampleData/`. Delete that folder once the feed reads from GRDB.
- Built so far: feed with Telegram-style bubbles and link previews, composer, attach menu (items are stubs), in-chat search, send animation, app icon.
- The iOS target compiles the same `App/` sources but its UI hasn't been tuned.
- Stubs: header ⋯, paperclip menu items, mic, and the "Unlock" tag chip in search.

## Plan (build and test after each step)
1. StatemonoKit: model, database, FTS search (with the đ fix), tests
2. App shell: feed, composer, paste, search, jump-to-message. **UI done for macOS on sample data.** Still to do: wire it to the database.
3. Metadata: fxtwitter for X, oEmbed (YouTube/TikTok/Vimeo/Spotify), OpenGraph, LPMetadataProvider fallback; images downsampled into the App Group
4. Share extension + App Group
5. Sync: undecided. Options are CloudKit now, my own server (PocketBase/Go) from the start, or no sync in v1. Don't run CloudKit and a server side by side. The server is what lets a Linux (Omarchy/Hyprland) desktop join.

## UI reference
- The target is Telegram for macOS, night theme. Colors and sizes in `App/Chat/Theme.swift` (`Theme`, `Metrics`) were measured from 2x screenshots, so measure new screens the same way rather than guessing.
- For behavior, read TelegramSwift (github.com/overtake/TelegramSwift) for macOS and Telegram-iOS for iOS. TelegramSwift is GPL-2.0 and built on its own AppKit table (TGUIKit), so port the mechanism, not the code.

## Known gotchas
- FTS5 `unicode61 remove_diacritics 2` strips Vietnamese tone marks (ở → o, Nguyễn → nguyen) but does NOT fold đ/Đ → d. This was verified in sqlite3. It needs a custom GRDB FTS5 wrapper tokenizer that maps đ→d, so "duong" finds "đường" while snippets still show the original text.
- The custom tokenizer must be registered on every connection that writes, including the share extension's. Once the FTS triggers exist, an insert fails with "no such tokenizer" otherwise. The extension may also be first to open the database, so it has to run migrations too. Put one database factory in StatemonoKit.
- Give the items table an explicit `INTEGER PRIMARY KEY` rowid. `VACUUM` can renumber implicit rowids and break an external-content FTS index. The rowid never leaves the device.
- GRDB `ValueObservation` doesn't see writes from other processes. The Mac app can be open while the share extension writes, so post a Darwin notification from the extension.
- SQLite in an App Group container can get the iOS app killed (`0xdead10cc`) if it holds a lock while suspended. Follow GRDB's "Sharing a Database" guide.
- In-chat search currently matches in memory (`App/Chat/ChatSearch.swift`): case- and diacritic-insensitive, đ = d, and every term must appear in the text or the preview's site name, title, or summary. Keep the same rules when it moves to FTS5.

### macOS feed and window (don't undo these)
- The window uses a hidden title bar and no toolbar. A toolbar swallows clicks on the floating header. `TrafficLightsAligner` moves the traffic lights down to line up with the header.
- The feed is a `VStack`, not a `LazyVStack`. The send animation needs exact heights, and the lazy stack only estimates rows it hasn't shown, which causes overshoot. The consequence: load messages from the database in pages, as Telegram does.
- No `.scrollPosition` binding on the feed: it snaps back to its stored value and undoes jumps. Jumps go through `ScrollViewReader` (`ScrollRequest` in `ChatView`).
- No `.defaultScrollAnchor(.bottom, for: .sizeChanges)`: it snaps the feed the instant a message is added.
- Sending uses `FeedScroller`, which reproduces TelegramSwift's transition: snap to the bottom, then slide the content up by the inserted height, 0.2s ease-out. SwiftUI's animated `scrollTo` on macOS ignores the requested duration and finishes in about 40ms.
- The search panel is an overlay under the header, not part of the top safe-area inset, so opening it doesn't move the feed.
- Inline timestamps reserve their space with invisible text at the end of the message. That reserve must end in visible characters (`"\u{00A0}00"`), because trailing spaces don't count toward a line's width.

## Working on the app
- After adding or removing files, run `xcodegen generate`. The `.xcodeproj` lists files explicitly.
- Build both schemes after UI changes. `App/` is shared, so a Mac change can break the iOS build.
- The terminal has no Screen Recording permission, so `screencapture` fails. To check the UI, render the app's own window in-process with `NSView.cacheDisplay`, which needs no permission. It can't see Core Animation layer animations, though.
- App icon: `Design/statemono-logo-icon.png` is the source. The iOS icon is a flattened, opaque, full-bleed 1024 image. The macOS icons put an 824pt body on a 1024 canvas with continuous corners of radius 185.4 and a soft shadow, at 16–1024px.

## Config
- IDs come from `APP_BUNDLE_ID` in project.yml (`com.statemono`). `DEVELOPMENT_TEAM` is still empty, and the App Group (step 4) needs it.
- Deployment targets: iOS 18 / macOS 15. Swift 6 language mode.
