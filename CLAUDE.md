# Statemono

Telegram "Saved Messages" for links: share or paste a link, it shows up as a chat bubble with a rich preview, and everything is full-text searchable. SwiftUI, one codebase for iPhone and Mac. See README.md for setup and layout.

## Design principles
- Local-first: SQLite (GRDB) on the device is the source of truth. The UI reads only from the local database.
- Share extensions stay tiny: they write the row to the shared App Group database and do nothing else (no metadata fetch).
- Deletes are tombstones (`deletedAt`), never hard deletes.
- All sync goes through one `SyncBackend` protocol so the backend can be swapped.
- Items: client-generated UUID `id`, integer rowid for FTS, `updatedAt` for last-write-wins, a dirty flag for pending uploads.

## Known gotchas
- FTS5 `unicode61 remove_diacritics 2` strips Vietnamese tone marks (ở → o, Nguyễn → nguyen) but does NOT fold đ/Đ → d. This was verified in sqlite3. It needs a custom GRDB FTS5 wrapper tokenizer that maps đ→d, so "duong" finds "đường" while snippets still show the original text.

## Plan (build and test after each step)
1. StatemonoKit: model, database, FTS search (with the đ fix), tests
2. App shell: feed, composer, paste, search, jump-to-message
3. Metadata: fxtwitter for X, oEmbed (YouTube/TikTok/Vimeo/Spotify), OpenGraph, LPMetadataProvider fallback; images downsampled into the App Group
4. Share extension + App Group
5. Sync: undecided. Options are CloudKit now, my own server (PocketBase/Go) from the start, or no sync in v1. Don't run CloudKit and a server side by side. The server is what lets a Linux (Omarchy/Hyprland) desktop join.

## Config
- IDs come from `APP_BUNDLE_ID` in project.yml (`com.statemono`). `DEVELOPMENT_TEAM` is still empty.
- Deployment targets: iOS 18 / macOS 15. Swift 6 language mode.
