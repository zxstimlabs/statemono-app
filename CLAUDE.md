# Statemono

Telegram "Saved Messages" for links: share or paste a link, it shows up as a chat bubble with a rich preview, and everything is full-text searchable. SwiftUI, one codebase for iPhone and Mac. See README.md for setup and layout.

## Design principles
- Local-first: SQLite (GRDB) on the device is the source of truth. The UI reads only from the local database.
- Share extensions stay tiny: they write the row to the shared App Group database and do nothing else (no metadata fetch).
- Deletes are tombstones (`deletedAt`), never hard deletes.
- All sync goes through one `SyncBackend` protocol so the backend can be swapped.
- Items: client-generated UUID `id`, integer rowid for FTS, `updatedAt` for last-write-wins, a dirty flag for pending uploads.

## Status
- The feed reads from the SQLite database (GRDB) in `Packages/StatemonoKit/Sources/StatemonoKit/Database/`. Messages, previews, and the image index survive relaunches.
- Built so far: feed with Telegram-style bubbles and link previews, composer, attach menu (items are stubs), message context menu (Copy Text and Delete work), in-chat search over all history, send animation, paging, app icon.
- Sending a link fetches its preview on the device (`Packages/StatemonoKit/Sources/StatemonoKit/LinkPreviews/`). X posts and ordinary websites are covered.
- The iOS target compiles the same `App/` sources but its UI hasn't been tuned.
- Stubs: header ⋯, paperclip menu items, mic, and the context menu's Reply, Translate, Edit, Pin, Forward and Select.

## Plan (build and test after each step)
1. StatemonoKit: model, database, FTS search (with the đ fix), tests. **Done.**
2. App shell: feed, composer, paste, search, jump-to-message. **Done for macOS, on the database.**
3. Metadata: fxtwitter for X, oEmbed (YouTube/TikTok/Vimeo/Spotify), OpenGraph, LPMetadataProvider fallback. **X and OpenGraph websites done.** Still to do: oEmbed and the LPMetadataProvider fallback. Images are cached on disk like Telegram (see Link previews).
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
- In-chat search uses the FTS5 table `itemSearch` (`AppDatabase.search`). It indexes the text and the preview's site name, title, and summary. Every query word must start a word there (`FTS5Pattern(matchingAllPrefixesIn:)`), ignoring case and tone marks, with đ = d. Bubbles highlight with the same folding (`SearchText` in `ChatSearch.swift`).

### Database
- Tables follow Telegram's model:
  - `item`: messages, with their preview's text inline and `previewImageID` pointing at a `media` row. It has the explicit rowid, UUID `id`, `updatedAt`, `deletedAt` tombstone, and `isDirty` flag from the design principles.
  - `media`: one row per image, holding its URL, pixel size, placeholder, cached file size, and last use. It also indexes `MediaStore`'s files, like Telegram's StorageBox.
  - `itemSearch`: the FTS5 index, kept in sync by triggers.
- `updatedAt` and `isDirty` change only on user edits. Saving a fetched preview doesn't touch them, because each device can fetch previews itself.
- `previewFetchedAt` is nil until a fetch finishes, and set even when the page had nothing to show. At launch, `ChatStore` retries links still missing a preview.
- The feed is a window anchored at its oldest loaded message (`observeFeed(from:)`), like Telegram's history view, not "the newest N". With a count window, each new message pushed the oldest out of the top, the content above jumped, and the send slide broke.
  - Launch loads the newest 50.
  - Reaching the top calls `loadOlder()` and moves the start back 50. `FeedScroller.willPrepend()` shifts the scroll position by the added height so nothing moves on screen.
  - Jumping to an older search result or date moves the start back to just before it.
- The database is at Application Support/<bundle id>/statemono.sqlite, a WAL `DatabasePool`. It moves into the App Group with the share extension (step 4). Opening it registers the tokenizer on every connection (`AppDatabase.configuration`).
- If the database can't be opened (a damaged file, or a failed migration), the app doesn't crash. `Library` (`App/Chat/DatabaseErrorView.swift`) shows the error and offers:
  - Try Again.
  - Start with a New Database…, after a confirmation. `AppDatabase.moveAside` renames the file and its WAL and SHM files to `statemono-unreadable-<local date>.sqlite` in the same folder, never deleting them, then opens a new database.
  - Show in Finder.
  Cached image files are left alone, so they're reused if the same links come back.

### Link previews
- x.com serves an empty JavaScript page to anything that isn't a known crawler, so post links go through the fxtwitter API (`api.fxtwitter.com/status/{id}`).
  - The preview copies Telegram's: site "X (formerly Twitter)", title "Name (@handle) on X", then the post text.
  - The first photo is fetched at `?name=medium`. Posts without media show the author's avatar as a small thumbnail.
- Websites are read with a Safari user agent, only up to `</head>` (1 MB cap).
  - Fields come from OpenGraph tags, then Twitter card tags, then `<title>` and `<meta name="description">`.
  - Image URLs resolve against the final URL, after redirects. A direct image link previews as the image itself.
- Large vs. small image follows TelegramSwift's `WPArticleLayout.isFullImageSize`: large for photo and video pages, X, Instagram, and pages without a description, unless the image is under 200px wide. Telegram's server can also mark media as large; `twitter:card = summary_large_image` stands in for that here. Everything else gets a 54pt thumbnail in the top-right corner.
- Image caching follows Telegram, per the owner's decision; research in the session of 2026-09-27 read both Telegram clones.
  - Disk is the cache. `MediaStore` is modeled on MediaBox: one file per image, named `http-<sha256 of URL>`, in Application Support/<bundle id>/Media, excluded from backups. Files are written atomically.
  - The disk store grows until the user cleans it up. Nothing is evicted automatically, matching Telegram's default of no size limit.
  - Cleanup methods exist for a future storage screen: `size()`, `removeAll()`, `trim(to:)` (least recently used first), and `removeUnused(since:)`. Reading a file marks it used, at most once an hour.
- Preview text is stored on the message's `item` row. The image's pixel size and tiny placeholder are stored on its `media` row. The placeholder, `PreviewPlaceholder`, is a ~40px JPEG of about 1KB, shown blurred until the image loads. It's Telegram's `immediateThumbnailData`, so previews never look empty, even offline or right after a relaunch.
- `PreviewImageLoader` reads memory, then disk, then the network.
  - Images are decoded at exactly the pixels the view draws (Telegram's `drawingSize`).
  - Every bubble showing the same image shares one download, which is cancelled only when no one is waiting (MediaBox's per-resource fetch).
  - The memory cache (`ImageCache`, least recently used, behind a `Mutex`) is small, 32MB, because re-reading from disk is cheap. It empties on memory pressure.
  - Don't go back to `NSCache`: it was measured ignoring its cost limit.
  - An image costs twice its pixel bytes, because the renderer keeps a copy of any image that has been drawn.
- All preview requests use `URLSession.uncached`, so nothing lands in `~/Library/Caches`. Images are kept in `MediaStore` instead.
- `RemoteImage` loads only once it's on screen, because the feed isn't lazy and every image view exists up front.
  - Images already on disk load right away.
  - Downloads wait until the image has stayed in view for 100ms, and scrolling away cancels them.
  - Off screen, a view lets go of its decoded image.
- Measured: after a relaunch, images come from disk with no network request. Scrolling past 120 large images stayed bounded (+52MB footprint at the end).
- Each link bubble has a reload button in its top-right corner, sized like the time and ticks. It re-fetches the preview, deletes the cached image from memory and disk, and spins while any fetch for that message is running.
- Bare domains ("example.com") are fetched over https; App Transport Security blocks plain http. If the Mac app is ever sandboxed, it needs `com.apple.security.network.client`.
- When the feed is at the bottom and content grows, for example when a preview arrives, `FeedScroller` follows it down. If the user has scrolled up, the feed stays put.

### macOS feed and window (don't undo these)
- The window uses a hidden title bar and no toolbar. A toolbar swallows clicks on the floating header. `TrafficLightsAligner` moves the traffic lights down to line up with the header. The header strip behind the avatar and between the controls drags the window (`WindowDragGesture`).
- The feed is a `VStack`, not a `LazyVStack`. The send animation needs exact heights, and the lazy stack only estimates rows it hasn't shown, which causes overshoot. The cost is that every row takes part in every scroll frame: measured medians are 8ms at 36 messages, ~11ms at 66–106, and 17ms (60fps) at 206. So the feed loads 50 messages at a time (see Database).
- Never read per-row geometry on every frame (`GeometryReader` or position-dependent `onGeometryChange` in bubbles). A GeometryReader in each bubble dropped a 200-message feed to 20fps. The window-pinned bubble gradient is a render-time `visualEffect { $0.brightness(...) }` on a solid fill. A clipped, offset gradient in `visualEffect` does not clip and spills over neighbors. A Metal shader would be exact, but Xcode 26 ships the Metal compiler as a separate download.
- No `.scrollPosition` binding on the feed: it snaps back to its stored value and undoes jumps. On macOS, jumps go through `FeedScroller`. `ScrollViewReader` (`ScrollRequest` in `ChatView`) is the iOS path and the fallback.
- No `.defaultScrollAnchor(.bottom, for: .sizeChanges)`: it snaps the feed the instant a message is added.
- All animated scrolling on macOS goes through `FeedScroller`: a closed-form, critically damped spring stepped by a `CADisplayLink`. SwiftUI's animated `scrollTo` on macOS ignores the requested duration and finishes in about 40ms.
  - Send reproduces TelegramSwift's transition: if scrolled up, jump to the old bottom, then slide up by the inserted height (response 0.25 ≈ Telegram's 0.2s ease-out).
  - Search and calendar jumps glide with response 0.4, and long jumps first snap to one screen away.
  - Re-targeting keeps velocity. Anything else moving the clip view cancels it, and Reduce Motion skips it.
  - The display link needs `preferredFrameRateRange` set, or it runs well below 120Hz.
- Search starts in the header's search field (focusing it opens the panel). The panel is an overlay under the field, not part of the top safe-area inset, so opening it doesn't move the feed.
  - There are two text fields, the search field and the composer, and leaving one focuses the other. Closing the search in any way (⌘F toggles it, Escape, ✕, a click in the feed) gives the composer the keyboard, as in Telegram, where the message field is the chat's default responder. On iOS nothing is focused instead, so the keyboard doesn't come up. `ChatFocus` in `ChatView` holds the focus for both fields.
  - Leaving the field with an empty query closes the search. Clicking the feed doesn't take focus from a text field on macOS, so the feed's scroll content has a tap gesture that closes an empty search. A gesture on the `ScrollView` itself never receives the click.
- Inline timestamps reserve their space with invisible text at the end of the message. That reserve must end in visible characters (`"\u{00A0}00"`), because trailing spaces don't count toward a line's width.

### Menus
- The attach menu and a message's context menu share `MenuPanel`, `MenuRow` and `MenuSeparator` (`Menu.swift`). The numbers come from TelegramSwift's `AppMenu`: 28pt rows, 13pt medium, an 18pt icon 15pt in, text at 42pt, 5pt separators, 4pt top and bottom. The 18pt corner radius comes from a screenshot of current Telegram; the July 2025 source says 10.
- The context menu (`MessageMenu.swift`) opens on right-click or Control-click anywhere on a message's row, as TelegramSwift's `TableRowView` does, beside the bubble included. SwiftUI's `.contextMenu` on macOS is a native `NSMenu`, which looks nothing like Telegram's, and macOS 15 SwiftUI has no secondary-click gesture. Instead, one `WindowEventMonitor` in `ChatView` catches the click, and `FeedScroller.contentPoint(of:)` plus `rowFrames` find the row. Clicks on the header, composer or search panel don't count.
- While the menu is open, the same monitor sends keys, scroll-wheel events and right-clicks to `MessageMenuState`; the overlay's backdrop catches left clicks outside. The monitor lives in `ChatView`, not the overlay, because the overlay stays in the window during its 0.2s fade-out and would keep swallowing events.
- iOS uses the system `.contextMenu` with the same items.
- Delete shows Telegram's alert ("This action can't be undone" / "Delete selected message?"), then `AppDatabase.deleteItem` writes the tombstone.
- Screenshots are in the display's color profile, not sRGB. Saturated colors shift: Telegram's red #EF5B5B reads as #DE6560 in a screenshot. Dark neutrals barely move. Convert a saturated color, or check it in the harness, before putting it in `Theme`.

## Working on the app
- After adding or removing files, run `xcodegen generate`. The `.xcodeproj` lists files explicitly.
- Build both schemes after UI changes. `App/` is shared, so a Mac change can break the iOS build.
- The terminal has no Screen Recording permission, so `screencapture` fails. An app can capture its own windows, though. To check the UI, build the `App/Chat` sources into a small scratch harness app that opens the same window.
  - For pixels, use `CGWindowListCreateImage` on the harness's own window. It's obsoleted in the SDK, so look it up with `dlsym`.
  - `NSView.cacheDisplay` is faster, but it misses masks, render-time effects, and Core Animation animations, so it can show bugs that aren't there.
  - For motion, log the clip view's bounds changes with timestamps.
  - Make the harness a regular, frontmost app. macOS throttles display links in windows that aren't in front.
  - For a synthetic click, queue the mouse-up (`NSApp.postEvent`) before sending the mouse-down. A text field tracks the mouse until the mouse-up arrives, so sending the two in order hangs.
  - Synthetic clicks can leave the harness window inactive, and then ⌘ shortcuts never arrive. Activate the window again before sending one.
  - Events posted with `NSApp.postEvent` go through `WindowEventMonitor`, so post synthetic right-clicks and keys that way. Synthetic scroll-wheel events never reached the feed, posted or sent with `CGEvent.postToPid`.
  - StatemonoKit depends on GRDB, so make the harness a SwiftPM executable package that depends on `Packages/StatemonoKit` by path. Copy `App/Chat/*.swift` into its sources on each build, and seed a database through `AppDatabase`.
- App icon: `Design/statemono-logo-icon.png` is the source. The iOS icon is a flattened, opaque, full-bleed 1024 image. The macOS icons put an 824pt body on a 1024 canvas with continuous corners of radius 185.4 and a soft shadow, at 16–1024px.

## Config
- IDs come from `APP_BUNDLE_ID` in project.yml (`com.statemono`). `DEVELOPMENT_TEAM` is still empty, and the App Group (step 4) needs it.
- Deployment targets: iOS 18 / macOS 15. Swift 6 language mode.
