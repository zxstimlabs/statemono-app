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
- Built so far: feed with Telegram-style bubbles and link previews, composer, attach menu (items are stubs), message context menu (Copy Text, Tags and Delete work), in-chat search over all history with typo tolerance and a results list (iPhone) or dropdown (Mac), Smart Search (finds links by meaning, with Apple's on-device model by default), Apple Intelligence tags, a Settings sheet from the header's gear (Appearance and Search pages), light and dark themes, send animation, paging, app icon, scroll-to-bottom button. On iOS, a hide-keyboard button.
- Sending a link fetches its preview on the device (`Packages/StatemonoKit/Sources/StatemonoKit/LinkPreviews/`). X posts and ordinary websites are covered.
- The iOS target compiles the same `App/` sources but its UI is only partly tuned. Its text follows the system Text Size (see UI reference), its keyboard behaves like Telegram-iOS's (see iOS keyboard), and its bubbles are as wide as Telegram-iOS allows (see UI reference).
- Stubs: paperclip menu items, mic, and the context menu's Reply, Translate, Edit, Pin, Forward and Select.

## Plan (build and test after each step)
1. StatemonoKit: model, database, FTS search (with the đ fix), tests. **Done.**
2. App shell: feed, composer, paste, search, jump-to-message. **Done for macOS, on the database.**
3. Metadata: fxtwitter for X, oEmbed (YouTube/TikTok/Vimeo/Spotify), OpenGraph, LPMetadataProvider fallback. **X and OpenGraph websites done.** Still to do: oEmbed and the LPMetadataProvider fallback. Images are cached on disk like Telegram (see Link previews).
4. Share extension + App Group
5. Sync: CloudKit with `CKSyncEngine` for Apple devices (owner, 2026-10-01), planned in `docs/sync-plan.md`. Other devices come later. Don't run CloudKit and a server side by side; a server (PocketBase/Go) is what would let a Linux (Omarchy/Hyprland) desktop join.
- Search beyond keywords: planned in `docs/search-plan.md`. Phases 1 (typo tolerance), 2 (Settings, results list), 3 (Smart Search) and 4 (Apple Intelligence tags, and Apple first) are built. Phase 0's `Tools/SearchEval` (a command-line package, not part of the apps) measures search on the links and 29 queries in `docs/search-test-links.md`. On them Apple's text model found 1 of 7 meaning queries and bge-small found 6. Still, the owner made Apple's on-device AI the first-class option on 2026-10-01, even where it isn't the best: Smart Search runs on Apple's model by default, and bge-small is an optional "More accurate" download. Phase 3b (Spotlight's semantic search) is paused. Build later phases only when the owner names them.
  - It's progressive. The app installs light, with nothing bundled, downloaded or running in the background.
  - English only.
  - Typo tolerance is part of Basic search, always on.
  - Smart Search (Apple's model, or bge-small when "More accurate" is on) and Apple Intelligence tags are separate steps on the Settings sheet's Search page, both on by default where they can run. Unsupported devices and OS versions get an explanation.
  - Everything runs on the device.

## UI reference
- The target is Telegram for macOS, night theme. Colors and sizes in `App/Chat/Theme.swift` (`Theme`, `Metrics`) were measured from 2x screenshots, so measure new screens the same way rather than guessing.
- Light mode is Telegram's "Day" theme (the owner's choice over Day Classic, 2026-10-01): blue bubbles with white text on plain white. Its values come from TelegramSwift's `whitePalette` and Telegram-iOS's `DefaultDayPresentationTheme`, not a screenshot yet. Each `Theme` color holds both (`Color(light:dark:)`, a dynamic `NSColor`/`UIColor`), so views use `Theme` colors, never `.white` or `.black`. Inside a bubble everything stays white in both themes.
- Text sizes come from `ChatTextSize` (`Theme.swift`, read through the environment). The Mac keeps its measured 13/12/11/12pt (message, preview, time, day pill). iOS copies Telegram-iOS's "Use System Text Size": the system body size snaps to Telegram's steps (14, 15, 16, 17, 19, 23, 26; 17 by default), messages and the composer use it, previews 14/17 of it, times 11/17, day pills 13/17.
- Bubble widths: the Mac keeps its measured caps (400pt text, 282pt previews, at least 56pt free on the left). iOS follows Telegram-iOS's `ChatMessageItemWidthFill`: the limit comes from the row's width (`Metrics.bubbleLeadingSpace`), and previews fill that width. Telegram's bubbles reach 43pt from the left edge of an upright phone; the owner found that too wide, so bubbles here leave 41pt more (`Metrics.extraLeadingSpace`) and reach 84pt (the owner moved it from 60pt to 68pt, 76pt, then 84pt, on 2026-09-30, for room to tap beside them). Past 500pt a bubble fills 85% of the row, 65% past 680pt.
  - `BubbleRow`, a `Layout`, applies it, because a layout is given the row's width without reading geometry in each bubble. `ChatView` measures the feed's width once (`feedWidth`), only to decode preview images at the width they're drawn.
  - On the right, the bubble ends 10pt from the edge on iOS, as in Telegram-iOS (`Metrics.bubbleTrailing` is 4pt plus the 6pt tail room), and 17pt on the Mac.
- Bubble content always gets the height it asks for (`CappedWidth` proposes a nil height). Given a fixed height, a VStack splits it among flexible children, and at large text sizes a preview's text lost lines to its image.
- For behavior, read TelegramSwift (github.com/overtake/TelegramSwift) for macOS and Telegram-iOS for iOS. TelegramSwift is GPL-2.0 and built on its own AppKit table (TGUIKit), so port the mechanism, not the code.

## Known gotchas
- FTS5 `unicode61 remove_diacritics 2` strips Vietnamese tone marks (ở → o, Nguyễn → nguyen) but does NOT fold đ/Đ → d. This was verified in sqlite3. It needs a custom GRDB FTS5 wrapper tokenizer that maps đ→d, so "duong" finds "đường" while snippets still show the original text.
- The custom tokenizer must be registered on every connection that writes, including the share extension's. Once the FTS triggers exist, an insert fails with "no such tokenizer" otherwise. The extension may also be first to open the database, so it has to run migrations too. Put one database factory in StatemonoKit.
- Give the items table an explicit `INTEGER PRIMARY KEY` rowid. `VACUUM` can renumber implicit rowids and break an external-content FTS index. The rowid never leaves the device.
- GRDB `ValueObservation` doesn't see writes from other processes. The Mac app can be open while the share extension writes, so post a Darwin notification from the extension.
- SQLite in an App Group container can get the iOS app killed (`0xdead10cc`) if it holds a lock while suspended. Follow GRDB's "Sharing a Database" guide.
- In-chat search uses the FTS5 table `itemSearch` (`AppDatabase.search`, in StatemonoKit's `Search/`). It indexes the text and the preview's site name, title, and summary. Every query word must start a word there, ignoring case and tone marks, with đ = d. A word that matches nothing as typed also tries other spellings from the index's vocabulary (`SearchVocabulary`, read through a temporary `fts5vocab` table on the writer's connection and cached until items change). Results come newest first with how they matched. Bubbles highlight the typed words and the other spellings, with the same folding (`SearchText` in `ChatSearch.swift`).

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
  - Jumping to a search result or date keeps 10 messages loaded above it (`ChatStore.jumpMargin`, `loadHistory(before:)`), moving the start back if it's older or too close to the top. Centering the oldest loaded message used to reach the top, and the next page loaded mid-jump: the iPhone ended at the top of history, and the Mac didn't move.
- The database is at Application Support/<bundle id>/statemono.sqlite, a WAL `DatabasePool`. On the Mac, Application Support is inside the sandbox container (see Config). It moves into the App Group with the share extension (step 4). Opening it registers the tokenizer on every connection (`AppDatabase.configuration`).
- If the database can't be opened (a damaged file, or a failed migration), the app shouldn't crash. `Library` (`App/Chat/DatabaseErrorView.swift`) shows the error and offers:
  - Try Again.
  - Start with a New Database…, after a confirmation. `AppDatabase.moveAside` renames the file and its WAL and SHM files to `statemono-unreadable-<local date>.sqlite` in the same folder, never deleting them, then opens a new database.
  - Show in Finder.
  Cached image files are left alone, so they're reused if the same links come back.
  - Known bug, found 2026-09-29, not fixed: a file that isn't a database crashes instead. Registering the tokenizer (`db.add(tokenizer:)` in `AppDatabase.configuration`) calls GRDB's `FTS5.api`, which hits `fatalError("FTS5 is not available")` when it can't prepare a statement on the damaged file. The test `a damaged file fails to open…` crashes the same way, on the commit before Phase 1 too.

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
- Known gaps, found in search Phase 0: Steam pages time out in the fetcher though `curl` loads them in about a second, and pages that redirect in the browser (meta refresh or script) show "Redirecting…". Sites with bot checks (IMDb, Goodreads, Stack Overflow, Allrecipes) give no preview.
- Bare domains ("example.com") are fetched over https; App Transport Security blocks plain http. The sandboxed Mac app can fetch only because of `com.apple.security.network.client`.
- When the feed is at the bottom and content grows, for example when a preview arrives, `FeedScroller` (Mac) and `FeedFollower` (iOS) follow it down with a 0.25s slide. If the user has scrolled up, the feed stays put.

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
  - SwiftUI's scroll view doesn't see moves made through the clip view's bounds. It keeps the position it last knew (the bottom, from launch) and puts the feed back there when the content changes size, so a page of history loading for a jump threw the feed to the bottom. `FeedScroller.settled()` posts the live-scroll notifications a trackpad scroll would after each of its moves comes to rest, and SwiftUI updates its position from them.
  - A jump issued while older messages are loading waits for them (`pendingJump` survives the prepend's shift), then glides from the rows' new frames.
- Search starts in the header's search field (focusing it opens the panel). The panel is an overlay under the field, not part of the top safe-area inset, so opening it doesn't move the feed.
  - There are two text fields, the search field and the composer, and leaving one focuses the other. Closing the search in any way (⌘F toggles it, Escape, ✕, a click in the feed) gives the composer the keyboard, as in Telegram, where the message field is the chat's default responder. On iOS nothing is focused instead, so the keyboard doesn't come up. `ChatFocus` in `ChatView` holds the focus for both fields.
  - Leaving the field with an empty query closes the search. Clicking the feed doesn't take focus from a text field on macOS, so the feed's scroll content has a tap gesture that closes an empty search. A gesture on the `ScrollView` itself never receives the click.
- Inline timestamps reserve their space with invisible text at the end of the message. That reserve must end in visible characters (`"\u{00A0}00"`), because trailing spaces don't count toward a line's width.

### Search results and Settings
- Settings is a sheet over the chat on both platforms (`App/Settings/SettingsView.swift`), opened by the header's gear. On the Mac, ⌘, and the app menu's Settings… open the same sheet through a focused scene value (`SettingsCommands`), not a Settings window.
  - Its first page lists Appearance and Search, with Telegram-iOS's settings icons (30pt tiles, radius 8; 20pt on the Mac). Each opens its own page in a `NavigationStack`, on the Mac too, where the sheet shows a back button. Native grouped `Form`s throughout; the owner likes the native look.
  - Appearance (`AppearanceSettings.swift`) is System, Light or Dark, per device in `UserDefaults` (`appearance`). System is the default, as in both Telegram apps. `appAppearance` applies it: the window's `overrideUserInterfaceStyle` on iOS, `NSApp.appearance` on the Mac. Not `preferredColorScheme`: on iOS 18, going back to System (nil) left the open sheet in the old appearance.
  - Inside a pushed page `dismiss` only goes back a page, so the iPhone's Done buttons call `closeSettings` from the environment.
  - The Search page (`SearchSettings.swift`) imports FoundationModels, which iOS 18 and macOS 15 lack. Xcode weak-links it on its own (`LC_LOAD_WEAK_DYLIB`, checked with `otool -l`); keep every use behind `#available(iOS 26, macOS 26, *)`.
- The search results list (`ChatSearch.rows`, loaded 100 at a time) has one form per platform. `SearchRowContent` and `SearchSnippet` pick each row's text, cut it around the first match and find the matched words, the way Telegram-iOS's search rows do.
- iPhone: Telegram-iOS's "Show as List" (`SearchResultsList`), an opaque page over the chat, under the header, search panel and composer.
  - It fades in over 0.2s, grows from 0.95 and sharpens from a 30pt blur while the chat behind shrinks to 0.95 (`setList(shown:)`), and reverses on the way out.
  - In list mode the counter reads "M messages" and taps back to the chat.
  - The older/newer arrows aren't in the search panel: as in Telegram-iOS, they float over the chat in `FeedButtons`, and hide in list mode.
- Mac: TelegramSwift's dropdown (`SearchDropdown`), a glass card under the search panel.
  - It shows while the search field has focus and there are results, at most half the chat tall.
  - The field's arrow keys move its cursor and wrap, Return opens the cursor's row, and Escape clears the cursor before it closes the search.
  - Opening a row, or using the panel's arrows, takes focus away, which closes it.

### Smart Search
- Smart Search finds links by meaning (docs/search-plan.md, Phases 3 and 4). It's on by default with Apple's on-device English model, `NLContextualEmbedding` (`AppleEmbedder`): the system provides it, and fetches its files the first time if they're missing, with a 90-second limit. Its token vectors are averaged, and links are compared centered (`TextEmbedder.centersVectors`: the average link vector subtracted from each), as Phase 0 measured it.
  - "More accurate Smart Search" downloads BAAI's bge-small-en-v1.5 (MIT, 133.7 MB) from Hugging Face and uses it instead. `SearchModel.bgeSmall` pins the revision and each file's SHA-256. A device that had downloaded it before Apple's model became the default keeps it on.
  - The files go to Application Support/<bundle id>/Models, excluded from backups (`SearchModelStore`). Turning "More accurate" off deletes them, and turning Smart Search off deletes them and every vector, each after a confirmation.
  - The switches are per device, in `UserDefaults` (`smartSearch.enabled`, on by default; `smartSearch.accurate`). Vectors record their model, so switching makes them again.
- `BertEmbedder` (StatemonoKit's `SmartSearch/`) runs the model with Accelerate, with its own WordPiece tokenizer and a memory-mapped `.safetensors` reader. Don't bring swift-embeddings into the app: it's about ten packages, a 40MB prebuilt library among them. `Tools/SearchEval` uses it only to check the app's version (`swift run -c release -Xswiftc -enable-testing SearchEval check`).
  - StatemonoKit defines `ACCELERATE_NEW_LAPACK` with `unsafeFlags`, for the current CBLAS interface. That works because the package is local; a remote dependency can't use unsafe flags.
  - The download uses a download task with its own session delegate (`FileDownload`). URLSession's async `download(from:delegate:)` never reported progress.
- `App/Chat/SmartSearch.swift` makes a vector for each link while the app is open: 16 at a time, newest first, off the main thread. Links wait for their preview, and Low Power Mode pauses the work. `AppDatabase.observeSearchContent` catches new links, edits, deletes and saved previews.
  - Vectors live in `itemVector`, with the model and revision, and the SHA-256 of the text they were made from (`AppDatabase.vectorText`: title, site, description, text). Changed text gets a new vector. Like previews, vectors don't touch `updatedAt` or `isDirty`.
- A search adds the 3 links closest in meaning that keyword search missed (`ChatSearch.related`). The list and dropdown show them after the matches, under Related. The arrows step through the matches, or through the related links when nothing matched ("1 of 3 related"), because after a right match they were mostly wrong in Phase 0.
  - While Smart Search is off and nothing is found, the search panel shows a Smart Search chip that opens Settings.

### Apple Intelligence tags
- `AppleIntelligenceTags` (`App/Chat/AppleIntelligenceTags.swift`) asks Apple Intelligence's content-tagging model (`SystemLanguageModel(useCase: .contentTagging)`, iOS/macOS 26+) for 3–8 keywords per link, with Phase 0's instructions (English tags whatever the text's language). It's on by default wherever Apple Intelligence is available, per device (`tags.enabled`).
  - Links are tagged one at a time while the app is open, newest first, once their preview is in. Low Power Mode pauses it. It took about 1.5s a link on this Mac.
  - Each link is tagged once. Re-tag All (Settings, `tags.retagAllSince`) and a link's Re-tag button ask again.
  - A refusal (guardrail, unsupported language, too long) marks the link tried. Any other failure (backgrounded, busy) stops the pass without marking it, and it resumes when the app comes back. Both error types count: `GenerationError` (iOS 26) and `LanguageModelError` (iOS 27).
- Tags are stored on `item` (`tags`, one per line; `tagsAttemptedAt`; `tagsOSVersion`) and indexed in `itemSearch`'s `tags` column, so keyword search matches them. Migration `v4 tags` recreated the FTS table, and GRDB rebuilt it. A result found only through tags is `SearchMatch.tag`.
  - Saving tags doesn't touch `updatedAt` or `isDirty`, so they never sync; each device makes its own.
- A message's menu gets Tags while tags are on (`MessageMenuItem.groups(showsTags:)`). It opens `TagsSheet`: the tags, or "Not tagged yet", and Re-tag. Choosing a tag closes the sheet and searches for it.
- The iPhone simulator here has neither Apple's text model nor Apple Intelligence. Smart Search times out to "isn't available right now", and tags wait. Test them on the Mac harness, or on a device.

### iCloud sync
- Messages sync through the user's private iCloud with Apple's `CKSyncEngine` (`docs/sync-plan.md`). StatemonoKit's `Sync/` holds the merge rules (`AppDatabase+Sync`) and the engine's delegate (`CloudKitSync`). `App/Chat/ICloudSync.swift` runs it and keeps the status, and `App/Settings/ICloudSettings.swift` is Settings › iCloud.
- What syncs: each item's UUID, text, link and dates. Text and link are in the record's `encryptedValues`. Previews, images and vectors stay per device. Deletes travel as `deletedAt`; records are never deleted. Last write wins by `updatedAt`.
- Uploads follow `isDirty`: `observeDirtyItems` hands new dirty items to the engine. A save clears the flag only if `updatedAt` didn't change while it was out. CloudKit's system fields for each item are kept in `itemSync`, and the engine's state in `syncState`. Applying a remote change never sets `isDirty` or touches `updatedAt` beyond the remote's own.
- Nothing local is ever deleted. Signing out, switching accounts, or a deleted zone marks everything dirty to go up again. Only a purge (the user deleting the app's data in iCloud's settings) seen by a device that had synced (`hasSyncedItems`) turns syncing off. A device's first fetch also reports zone deletions from before it existed.
- The container comes from the Info.plist key `StatemonoICloudContainer` (`Config/Statemono-*-Info.plist`, merged into the generated plist). Builds without it, such as the test harnesses, don't sync, because CloudKit needs the entitlements.
- A thousand synced messages can arrive at once into a feed showing all of a short history; `ChatStore.show` then re-anchors to the newest page, since the feed isn't lazy.
- CloudKit traps (`EXC_BREAKPOINT` in `CKContainer(identifier:)`) on a container the app isn't entitled to. It's a trap, not an exception, so it can't be caught. `CloudKitSync.canUse` reads the app's own signed entitlements first (`Entitlements`: the code signature's entitlements blob, or a simulator build's `__TEXT,__entitlements` section). Without the container or push, sync stays off and Settings says the build can't use iCloud.
- `CloudKitSync` logs each engine event at debug level: `log stream --level debug --predicate 'subsystem == "com.statemono"'`.
- Testing sync on this Mac (`docs/sync-plan.md`, Built): two copies of a scratch build with the real bundle ID `com.statemono`, unsandboxed, with the iCloud entitlements, each with its own `STATEMONO_DATA_DIR` (a debug-only switch for the database and media folder). Start them with `open -n --env STATEMONO_DATA_DIR=<folder> <app>`; a process started from a shell command dies when the command ends. A scratch App ID got "Invalid bundle ID for container" for over 15 minutes, while `com.statemono` worked at once. Delete the test zone afterwards, or a debug build of the real app downloads the test data. The unsandboxed copies keep their settings in `~/Library/Preferences/com.statemono.plist`, which `defaults <domain>` doesn't reach while a sandbox container for the bundle ID exists; pass the file's path instead.
- CloudKit's environments: debug-signed builds use Development, TestFlight and the App Store use Production. A new field or record type must be deployed to Production in the CloudKit Console (owner) before a TestFlight build that uses it.
- This Xcode 27 install has no Simulator app, only `simctl`, so no simulator can be signed into iCloud. Test iPhone sync on a device through TestFlight.

### Menus
- The attach menu and a message's context menu share `MenuPanel`, `MenuRow` and `MenuSeparator` (`Menu.swift`). The numbers come from TelegramSwift's `AppMenu`: 28pt rows, 13pt medium, an 18pt icon 15pt in, text at 42pt, 5pt separators, 4pt top and bottom. The 18pt corner radius comes from a screenshot of current Telegram; the July 2025 source says 10.
- The context menu (`MessageMenu.swift`) opens on right-click or Control-click anywhere on a message's row, as TelegramSwift's `TableRowView` does, beside the bubble included. SwiftUI's `.contextMenu` on macOS is a native `NSMenu`, which looks nothing like Telegram's, and macOS 15 SwiftUI has no secondary-click gesture. Instead, one `WindowEventMonitor` in `ChatView` catches the click, and `FeedScroller.contentPoint(of:)` plus `rowFrames` find the row. Clicks on the header, composer or search panel don't count.
- While the menu is open, the same monitor sends keys, scroll-wheel events and right-clicks to `MessageMenuState`; the overlay's backdrop catches left clicks outside. The monitor lives in `ChatView`, not the overlay, because the overlay stays in the window during its 0.2s fade-out and would keep swallowing events.
- iOS has its own menu, built like Telegram-iOS's (`ContextControllerImpl`, `ContextControllerExtractedPresentationNode`), with the same items. `FeedContextMenu.swift` handles the press, and `FeedContextMenuOverlay.swift` draws the menu.
  - One long-press recognizer on the feed's scroll view finds the bubble from frames the bubbles report in content coordinates. After 0.12s the bubble shrinks for 0.2s (by 15pt across, no smaller than 70%), then the menu opens with a haptic. Moving the finger 10pt first cancels it and the feed scrolls.
  - On opening, every other gesture following the finger is cancelled (`UITouch.gestureRecognizers`), so lifting it doesn't open a link or reload a preview under it, and moving it doesn't scroll the feed.
  - The bubble in the feed is hidden (`isExtracted`) while a copy (`BubbleView`, with the shade it had there, `bubbleShade`) shows in the menu. It moves up or down only: into view if it was under the header (8pt below the safe area), then up until the actions fit 7pt below it, 10pt above the bottom safe area. It never goes higher than that top line.
  - A bubble too tall for that opens scrolled to its bottom, with its top cut off by the screen's edge, and the menu scrolls to show the rest. The system menu kept a tall preview inside its own margins and cut it off about 60% down the screen. iOS 26's scroll edge blur is turned off there.
  - Motion: Telegram's spring (mass 5, stiffness 900, damping 104, about 0.42s) for the bubble and for the actions, which grow from 0.01 out of the middle of the bubble's old bottom edge and fade in over 0.05s. The bubble grows back from the press over 0.2s. Closing reverses it all over 0.2s ease-in-out, then runs the chosen item.
  - Behind it the chat is blurred (`.systemUltraThinMaterialDark`, whose radius animates) and dimmed with black at 60%, Telegram's dark `contextMenu.dimColor`, over 0.2s. A tap anywhere but the actions closes the menu.
  - Actions (`ContextControllerActionsStackNode`): at least 220pt wide, lined up with the bubble's outer edge 7pt in and at least 12pt from the screen's edges. Rows are 11pt above and below the title, in the chat's text size. The icon's 32pt column sits 20pt in, the title at 60pt. 10pt padding top and bottom, 20pt group gaps with a 1pt white 15% line inset 18pt, a pressed row lit white 10% in a rounded rectangle inset 10pt, corner radius up to 30. It's glass on iOS 26 and #1C1C1C at 85% over a blur before that. Delete is #EB5545.
  - VoiceOver gets a Message Menu action on each bubble that opens it.
  - Don't go back to SwiftUI's `.contextMenu`. On the device (iOS 26+), SwiftUI replaced the open menu once, 0.5–2s after it opened, around a keyboard-frame notification that presenting a menu posts: the menu cross-faded into a fresh copy and a scrolled menu jumped back to its top. The simulator never showed it, and making rows `Equatable` (`FeedMessageRow`, still used) didn't stop it. UIKit's `UIContextMenuInteraction` fixed that, but it's what cut tall bubbles off.
- Delete shows Telegram's alert ("This action can't be undone" / "Delete selected message?"), then `AppDatabase.deleteItem` writes the tombstone.
- Screenshots are in the display's color profile, not sRGB. Saturated colors shift: Telegram's red #EF5B5B reads as #DE6560 in a screenshot. Dark neutrals barely move. Convert a saturated color, or check it in the harness, before putting it in `Theme`.

### iOS keyboard
- The keyboard comes up only when a field is tapped. Like Telegram-iOS, the composer isn't focused when the chat opens (the Mac still focuses it).
- A tap anywhere in the feed puts the keyboard away: beside a bubble, on one, or above them. Telegram-iOS adds one tap recognizer to the whole history list (`ChatControllerNode.swift`). Here it's the same: a `UITapGestureRecognizer` on the feed's `UIScrollView` (`FeedTapToDismiss`), enabled only while a field has focus. It recognizes alongside everything else and lets touches through, so links still open. A SwiftUI `TapGesture` on the `ScrollView` worked on iOS 26 but missed taps on iOS 18. The search results list, which covers the feed, puts the keyboard away on a tap the same way.
- The composer sits 8pt (`Metrics.composerBottom`) above the keyboard, as in Telegram-iOS (`inputPanelsInset`). Nothing goes between them: an earlier hide-keyboard row under the composer left a gap, and the owner had it removed.
- The floating buttons (`FeedButtons`, see Scroll-to-bottom button) add Hide Keyboard on iOS, above Scroll to Bottom, while the keyboard is up (`keyboardWillShow`/`keyboardWillHide`). Telegram-iOS has none; the owner asked for it.
  - It floats over the feed instead of sitting in a row. A `.keyboard` toolbar would cover the composer on iOS 26 (Apple forums thread 798598), and the iPhone ignores `inputAssistantItem` buttons.

### Composer and search focus, edge fades
- A focused text field's glass grows 3pt above and below it (36 → 42pt), and its corners round to match, over `Metrics.focusAnimation` (0.25s smooth). That's the composer's field and the header's search field, on both platforms; the owner asked for it. Neither Telegram does it.
  - Only the glass grows (`chromeBackground(_:outset:)`), not the layout, so the feed, the composer's circles, the header and the traffic lights stay put. The search panel moves down by the same 3pt while the field has focus.
  - On the Mac the composer has focus by default, so it's usually the large one.
- `FeedEdgeFade` (`FeedFade.swift`) fades messages out as they scroll behind the header or the composer, like Telegram-iOS's two `WallpaperEdgeEffectNode`s. It's the chat background laid over the feed, on Telegram's eased curve (sampled from its 90 stops), then solid out to the edge.
  - Bottom: starts 20pt above the composer's field and fades in over 60pt, then covers everything to the bottom edge, behind the keyboard too.
  - Top: fades in over 80pt, clear 34pt below the header, then covers the header and the status bar. Telegram adds a variable blur of radius 1 there, barely visible; it's left out.
  - Both are fully opaque at the edge, as the owner asked. Telegram stops at 0.85 on a plain background.
  - They're overlays on the feed, under the header, composer, search panel and floating buttons, and they don't take touches, so right-clicks and taps reach the messages under them. Each is positioned from the feed's safe area and overflows outward. A `GeometryReader` that ignores the safe area reads its insets as 0, so that approach put the fade off screen.
  - TelegramSwift has no fade at either edge.

### Scroll-to-bottom button
- `FeedButtons` (`FeedButtons.swift`) is an overlay on the composer, stacked on its top edge at the trailing end, so it moves with the composer and keyboard and adds no inset. It used to be an overlay on the feed, placed from the feed's safe area; on iOS 18 that put the Hide Keyboard button in the middle of the screen. The buttons are 36pt glass circles (`chromeBackground`) in the mic button's column, and Scroll to Bottom has Telegram's 18×9 down chevron.
- iOS copies Telegram-iOS's `ChatHistoryNavigationButtons`:
  - Shows 40pt or more above the newest message (`FeedFollower.isAwayFromBottom`).
  - 12pt above the composer's field, 12pt between stacked buttons. A hidden button's slot closes, so the one above slides down. Telegram's buttons are 40pt, the size of its input buttons.
  - Grows in from 0.2 scale while fading in, over 0.3s on cubic-bezier(0.38, 0.7, 0.125, 1), and shrinks out the same way. The chevron is a 1.5pt stroke.
  - A tap glides in 0.3s on Telegram's slide curve, cubic-bezier(0.33, 0.52, 0.25, 0.99). From more than a screen away it first jumps to one screen above the bottom.
- The Mac copies TelegramSwift's `ChatNavigationScroller`:
  - Shows 80pt or more above the newest message (`FeedScroller.isAwayFromBottom`). That's measured from where a glide is heading, and a pending send counts as the bottom, because the Mac's slides are animated scroll positions and the button would flash during every send and followed preview.
  - 18pt above the composer's field. TelegramSwift also sits it 18pt in from the edge; here it lines up with the mic and the header's ⋯ instead.
  - Fades in and out over 0.2s, ease-out, with no scaling. A 1pt chevron and TelegramSwift's shadow (blur 5, black at 0.1, 2pt down).
  - A click glides like a search jump (response 0.4), snapping to a screen away first. TelegramSwift animates the whole way in 0.35s with a slight overshoot.
  - Right-clicking it doesn't open the message menu under it; SwiftUI's hit test puts it outside the scroll view, as with the search panel.
- `FeedFollower` (`FeedFollower.swift`) moves the feed with the keyboard, like Telegram-iOS's `ListView` inset fix.
  - Whatever the scroll position, the messages move by exactly the change in the bottom inset. Only the ends clamp.
  - SwiftUI raises the composer and gives the feed's `UIScrollView` the new inset (as safe area, in `adjustedContentInset`). It never moves the scroll position, so the keyboard used to slide over the newest messages.
  - UIKit posts `keyboardWillChangeFrameNotification` inside the keyboard's animation block (a 0.383s spring on iOS 26). That holds on hide too, even when the notification's duration says 0. A `contentOffset` set in the handler moves with the keyboard frame for frame.
  - SwiftUI's own observer runs first. By the handler, the new inset is applied, and on hide the offset is already clamped. So each move starts from the resting offset and inset that `onScrollGeometryChange` last recorded.
  - The same callback catches the composer growing or shrinking a line. That move is instant, like the field's.
  - It is iOS's `FeedScroller` for content, too. Growth at the bottom (a preview arriving) and sends slide like the Mac's: `UIView.animate(springDuration: 0.25)` on `contentOffset`, and a send from further up first jumps to where the bottom was. `willPrepend()` keeps older pages, including a search jump's, from pulling the feed down.
  - Take the content height from SwiftUI's `ScrollGeometry`. The `UIScrollView`'s `contentSize` catches up a frame later, and read there, previews and sends went unseen.
  - It's skipped while a finger drags the feed.
  - Not `.defaultScrollAnchor(.bottom, for: .sizeChanges)`. That follows the keyboard only at the very bottom, because only the scroll view's insets change, not its frame.
- The chat background extends under the keyboard (`ignoresSafeArea()`), because the iOS 26 keyboard shows the app behind its rounded top corners.

## Working on the app
- After adding or removing files, run `xcodegen generate`. The `.xcodeproj` lists files explicitly.
- Build both schemes after UI changes. `App/` is shared, so a Mac change can break the iOS build.
- The terminal has no Screen Recording permission, so `screencapture` fails. An app can capture its own windows, though. To check the UI, build the `App/Chat` sources into a small scratch harness app that opens the same window.
  - For pixels, use `CGWindowListCreateImage` on the harness's own window. It's obsoleted in the SDK, so look it up with `dlsym`. Pass the window's ID (`optionIncludingWindow`), never a screen rect: on 2026-10-01 a rect capture took in the owner's other windows and macOS asked to let the terminal bypass the screen-sharing picker.
  - `NSView.cacheDisplay` is faster, but it misses masks, render-time effects, and Core Animation animations, so it can show bugs that aren't there.
  - For motion, log the clip view's bounds changes with timestamps.
  - Make the harness a regular, frontmost app. macOS throttles display links in windows that aren't in front. Started from the terminal, it may stay behind the app in front; then posted ⌘, didn't open Settings, but a synthetic click on the gear did.
  - For a synthetic click, queue the mouse-up (`NSApp.postEvent`) before sending the mouse-down. A text field tracks the mouse until the mouse-up arrives, so sending the two in order hangs.
  - Synthetic clicks can leave the harness window inactive, and then ⌘ shortcuts never arrive. Activate the window again before sending one.
  - The composer isn't focused when the harness opens. Click it before posting key events to type.
  - Events posted with `NSApp.postEvent` go through `WindowEventMonitor`, so post synthetic right-clicks and keys that way. Synthetic scroll-wheel events never reached the feed, posted or sent with `CGEvent.postToPid`.
  - StatemonoKit depends on GRDB, so make the harness a SwiftPM executable package that depends on `Packages/StatemonoKit` by path. Copy `App/Chat/*.swift` and `App/Settings/*.swift` into its sources on each build, and seed a database through `AppDatabase`.
- For iOS, use the simulator. `xcrun simctl io <device> screenshot` works without Screen Recording permission. An iOS 18.6 runtime is installed too, with the simulator "iPhone 16 Pro iOS18", for iOS 18 bugs. `xcodebuild -downloadPlatform iOS -buildVersion 18.6` reported it unavailable, but the runtime arrived anyway (`xcrun simctl runtime list`). To tap and type, make a scratch xcodegen project with an app target over `App/` (its own bundle ID) and a UI-test target. `XCUIScreen.main.screenshot()` saves frames, and `TEST_RUNNER_<NAME>` passes environment variables to the tests.
  - `simctl install` can hang on a simulator's first boot. Shut it down and boot it again.
  - To seed, copy a database made with `AppDatabase` into Application Support/<bundle id> in the app's data container (`xcrun simctl get_app_container <device> <bundle id> data`).
  - For motion, `xcrun simctl io <device> recordVideo` also works without the permission. There's no ffmpeg; read frames with `AVAssetImageGenerator`.
  - To watch the feed's `UIScrollView`, add an Objective-C file with a `constructor` function to the harness target. It can log each frame from a `CADisplayLink`, comparing the model offset with the presentation layer's.
- App icon: `App/AppIcon.icon`, made by the owner in Icon Composer, serves both apps. It has a dark gradient fill and one SVG layer, the disc with the asterisk. Edit it in Icon Composer (Xcode › Open Developer Tool); `Design/statemono-logo-icon.png` is the original flat artwork.
  - Xcode compiles it into `Assets.car`: the layered icon for macOS/iOS 26+, plus flat images for older systems (the Mac's include 1024px, which App Store Connect requires; the iPhone's include dark and tinted).
  - There's no `AppIcon.appiconset` any more. With a `.icon` of the same name, Xcode ignores the set on every OS version.
  - Old-style Mac icons (artwork on a transparent canvas with a shadow) show on a grey tile on macOS 26+. The system only draws an icon at full size when it fills its rounded-square shape.

## Config
- IDs come from `APP_BUNDLE_ID` in project.yml (`com.statemono`). `DEVELOPMENT_TEAM` is Pyhash LLC's paid team (`8G6DC3A5B8`); the free personal team can't use TestFlight or App Groups.
- TestFlight: both apps ship with the same version and build number. Every upload needs a higher `CURRENT_PROJECT_VERSION` in project.yml. The App Store Connect app has iOS and macOS.
  - iOS: archive unsigned, then sign the archived app ad hoc with its entitlements, so the export keeps them:
    1. `xcodebuild archive -scheme Statemono-iOS -destination 'generic/platform=iOS' -archivePath <path> CODE_SIGNING_ALLOWED=NO`
    2. `sed 's/$(APP_BUNDLE_ID)/com.statemono/g' Config/Statemono-iOS.entitlements > <expanded>`
    3. `codesign --force --sign - --entitlements <expanded> --generate-entitlement-der <path>/Products/Applications/Statemono.app`

    A signed archive fails because the team has no registered iPhone, which a development profile needs. Without step 3 the App Store copy has no iCloud or push entitlements. TestFlight build 19 shipped that way, and CloudKit trapped at launch. Check an export with `-exportArchive` and `destination export`, then `codesign -d --entitlements :-` on the app in the .ipa. It should show `aps-environment` production and the container.
  - macOS: archive signed: `xcodebuild archive -scheme Statemono-macOS -destination 'generic/platform=macOS' -archivePath <path> -allowProvisioningUpdates`. It signs with the team's Apple Development certificate. Don't archive it unsigned: the entitlements (sandbox, network) are part of the signature.
  - Then, for either, `xcodebuild -exportArchive -allowProvisioningUpdates` with export options `method app-store-connect`, `destination upload`, `signingStyle automatic`, `teamID 8G6DC3A5B8`, `manageAppVersionAndBuildNumber false`. The export signs for the App Store and uploads with the Xcode account (for the Mac, as a signed .pkg).
- The Mac app is sandboxed (`Config/Statemono-macOS.entitlements`, generated from project.yml): App Sandbox plus `com.apple.security.network.client`, with category Productivity.
  - Its files live in `~/Library/Containers/com.statemono/Data/Library/Application Support/com.statemono`. The unsandboxed builds' data in `~/Library/Application Support/com.statemono` was left behind on purpose.
  - The terminal can't read or write that container ("Operation not permitted"). To seed a database for a test, use a scratch copy of the app with a different bundle ID, or Finder.
- Deployment targets: iOS 18 / macOS 15. Swift 6 language mode.
