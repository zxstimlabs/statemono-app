# Search plan: progressive search

Status: draft, updated 2026-09-29. No app code yet. Phase 0 is under way: the test tool, the link snapshot, tags and speed are done, and recall waits for the owner's queries (see Phase 0 results).

## The idea

The app installs light and stays light:
- **Nothing extra at install:** no models are bundled, nothing downloads, and no work runs in the background.
- **Smarter search is opt-in:** people turn it on in a Smart Search section, in steps that match what they need. Each step says what it downloads and does.
- **Everything runs on the device**, using Apple's models. Nothing is sent to a server.
- **Unsupported devices get an explanation:** when a device or OS can't use a step, the section says why in plain words, instead of hiding the step or failing silently.

## Today

In-chat search goes through the FTS5 table `itemSearch` (`AppDatabase.search`).
- Every query word must start a word in the message text or its preview's site name, title or description.
- Matching ignores case and accents (`StatemonoTokenizer`).
- Results come back in date order. The panel under the search field steps through them in the chat ("N of M", up and down), and bubbles highlight the matched words (`SearchText`).
- There's no typo tolerance and no sense of meaning.

## Decisions

| Question | Decision |
|---|---|
| Rollout | Progressive: light by default, opt-in steps in a Smart Search section, on-device only, with explanations for unsupported devices |
| Engine for meaning-based search | Apple's built-in text vectors (`NLContextualEmbedding`), behind a swappable interface |
| First on-device model feature | Tags at save time |
| Minimum OS | Stays iOS 18 / macOS 15; model features only on iOS/macOS 26+ |
| Scale | 4–10 links a day, depending on the person: about 1,500–3,650 a year |
| Language | English only |
| Typo tolerance | Part of Basic, always on, no switch. It needs no download and runs on every device the app supports (see How a search works) |
| How results are shown | Both: stepping through the chat, plus a list |
| Related results | In both places, as Telegram treats its results: the list's Related section, and up/down stepping after the keyword matches |
| Mac results list | TelegramSwift's dropdown under the search field |
| Tags | Used by search, and shown per message: long press (right-click on the Mac) → Tags opens a sheet with that message's tags. No editing. Re-tag All in Settings, and Re-tag for one link in its Tags sheet; nothing re-tags on its own |
| Settings | A gear button replaces the header's ⋯ on both platforms and opens Settings as a sheet, the same on both, with the Smart Search section |
| Prompting Smart Search | A chip in the search panel opens the Smart Search section |
| Test data | About 90 links to popular sites, chosen by Claude (`search-test-links.md`); the owner writes the queries |

## Tiers

| Tier | What it does | Downloads | Background work | Needs | Default |
|---|---|---|---|---|---|
| **Basic** | Keyword search as today, plus typo tolerance | None | None | Any supported OS (iOS 18 / macOS 15) | On |
| **Smart Search** | Related results by meaning, in the results list and when stepping | Apple's English text model, one time (size measured in Phase 0) | Makes a vector for each link, once, then one per new link | iOS 18 / macOS 15 (the API is iOS 17+) | Off |
| **Apple Intelligence tags** | 3–8 tags per link, generated on device, so keyword search finds related words | None from the app; Apple Intelligence brings its own model | Tags each link once, then each new link | iOS/macOS 26+, an Apple Intelligence device, Apple Intelligence turned on | Off |
| Later | Understanding natural-language questions, Ask with citations, a larger bundled vector model, system Spotlight | Depends on the step | Depends on the step | Depends on the step | Off |

Each tier works on its own. Tags don't need Smart Search, and Smart Search doesn't need Apple Intelligence.

## Settings and the Smart Search section

### Where it lives

- **Gear button:** on both platforms, a gear replaces the header's ⋯ button (a stub today) and opens Settings. Smart Search is a section there.
- **A sheet on both:** Settings is a sheet over the chat on the Mac too, not the Mac's separate Settings window, so the two apps feel the same. On the Mac, ⌘, opens the same sheet.
- **Chip in search:** while Smart Search is off, the search panel shows a Smart Search chip. It opens Settings at the Smart Search section. Once Smart Search is on, the chip is gone.

### What each row shows

One row per tier, with a switch, one sentence on what it does, and a status line.

**Basic search:** always on, with no switch. It only explains what's included, typo tolerance among it.

**Smart Search**, status by state:
- **Off:** "Find links by meaning, even without the same words. Downloads a language model from Apple (about N MB)."
- **Downloading:** "Downloading from Apple…" with progress if the API reports it, otherwise a spinner.
- **Preparing:** "Preparing your links… 420 of 1,240". This runs while the app is open and pauses in Low Power Mode.
- **Ready:** "On. 1,240 links ready."
- **Download failed:** "Couldn't download the model. Check your connection and try again." with a Retry button.

**Apple Intelligence tags**, status by state:
- **Off:** "Uses Apple Intelligence to add keywords to each link, so searches find related words."
- **Tagging:** "Tagging your links… 300 of 1,240".
- **Ready:** "On. 1,240 links tagged." with a Re-tag All Links… button (see Re-tagging).
- **Re-tagging:** "Re-tagging your links… 300 of 1,240".
- **Needs an update** (older than iOS/macOS 26): "Needs iOS 26 or later." (on the Mac, "macOS 26"). The switch is disabled.
- **Device not eligible** (`.unavailable(.deviceNotEligible)`): "This iPhone doesn't support Apple Intelligence." (on the Mac, "This Mac"). The switch is disabled.
- **Apple Intelligence off** (`.appleIntelligenceNotEnabled`): "Turn on Apple Intelligence in Settings to use this." The switch is disabled until it's on.
- **Still downloading** (`.modelNotReady`): "Apple Intelligence is still getting ready. Try again later."

**Storage:** a line showing how much space vectors and tags use.

### Turning things off

- **Stops the work:** turning off stops new work and removes that tier's derived data from the database, after a confirmation. That means vectors for Smart Search, and tags plus their index column for tags.
- **Apple's model files stay:** the system manages Apple's downloads, and there's no API to delete them. The section says so.
- **Turning back on** rebuilds from scratch.

## What stays the same

- **Share extension:** it still only writes the row. Vectors and tags are computed later by the app, only when their tier is on.
- **Derived data:** vectors and tags don't change `updatedAt` or `isDirty`, the same rule as saved previews.
- **Sync:** each device computes its own, and sync (plan step 5) won't carry them. Settings are per device too, since devices differ in what they support.
- **Tombstones:** deleted messages never appear in results.

## What the platform gives us

Checked in the iOS 27 and macOS 27 SDKs.

- **FoundationModels** (`SystemLanguageModel`), iOS/macOS 26+:
  - It runs only on devices with Apple Intelligence turned on. `availability` reports `deviceNotEligible`, `appleIntelligenceNotEnabled` or `modelNotReady`, one per explanation above.
  - It has a tagging mode, `SystemLanguageModel(useCase: .contentTagging)`, and structured output (`@Generable`).
  - There is no embeddings API, and the app can't download this model; the system does when Apple Intelligence is turned on.
  - iOS/macOS 27 add `PrivateCloudComputeLanguageModel`, a server model. It's out of scope while search stays on device.
- **NaturalLanguage** `NLContextualEmbedding`, iOS 17+:
  - There's one model per writing system; English uses the Latin one.
  - The model files download over the air on request (`hasAvailableAssets`, `requestAssets()`), which is exactly the opt-in download above. `load()` fails until they're there.
  - It returns one vector per token, so we average them into one vector per link.
  - It works best on a sentence or paragraph, and longer input is cut at `maximumSequenceLength`.
  - It wasn't trained for search, so its quality is the main risk; Phase 0 measures it.
- **Core Spotlight** `CSUserQuery` (iOS 18 / macOS 15) does semantic search over indexed app content. It's a candidate for the later "system Spotlight" step.
- **SQLite:** the SDKs ship SQLite 3.54, which has FTS5, `fts5vocab`, and the trigram tokenizer with `remove_diacritics`. `fts5vocab` comes with FTS5 itself, so iOS 18 and macOS 15 have it too.

## How a search works

Each tier adds a source to the same query.

### Basic: keyword matches, as you type

This is today's prefix search, widened with typo tolerance.

- **Typo tolerance:**
  - Each query word, folded the way the tokenizer folds (lowercase, no accents), is compared against the index's vocabulary. `fts5vocab` over `itemSearch` holds exactly those folded terms.
  - Allowed edits (Damerau–Levenshtein distance): 1 for words of 4–7 letters, 2 for 8 or more. Words of 3 letters or fewer must match exactly.
  - The word still being typed is compared against vocabulary word beginnings of the same length, so "sqlte" finds "sqlite" before the word is finished.
  - Each query word gets at most about 10 alternatives, the most common first.
  - The FTS query becomes, for each word: `(word* OR alternative OR …)`, with every word still required.
- **Always on:** it needs only SQLite's FTS5, which every supported OS has, and a little Swift. There's nothing to download and no switch.
- **Highlighting:** bubbles highlight the typed words and the alternative words that matched. Both are already folded, so `SearchText` handles them as it does now.
- **Timing:** runs on every keystroke, debounced 0.2s as Telegram-iOS does (`ChatControllerUpdateSearch.swift:96`).
- **Cost:** a vocabulary lookup, with no download and no background work.

### Smart Search: related matches, by meaning

- **Where it lives:** an `Embedder` interface in StatemonoKit (model ID, revision, dimension, text → vector). The first implementation uses `NLContextualEmbedding` for English: token vectors are averaged, then normalized to length 1.
- **Centered:** before comparing, the average of all link vectors is subtracted from each link's vector and from the query's, then they're normalized again. The average is recomputed when the vectors load. This spreads the scores out, and it ranked better in Phase 0.
- **What gets a vector:** preview title, site name, description and message text, trimmed to the model's limit.
- **Storage:** in SQLite, one vector per message (see Database changes). At a few KB per link, a year of links takes a few MB.
- **Query:** the query gets its own vector. The app keeps all link vectors in memory and compares them with a dot product using Accelerate. Brute force is fine up to tens of thousands of links, which is years of saving at 4–10 a day.
- **What counts:** the 3 most similar links that keyword search didn't already match. There's no similarity cutoff: in Phase 0 right and wrong links scored about the same, so no cutoff could tell them apart. The owner's queries confirm the number.
- **When it runs:** as you type, with keyword search's 0.2s debounce. A query's vector took 10ms on this Mac in Phase 0; iPhone timing is checked in Phase 3.
- **Model files missing or failing to load:** the tier shows as not ready in the section, and search behaves like Basic.
- **Swapping later:** a bundled Core ML model (such as EmbeddingGemma or an e5 model, about 100–200MB) can implement the same interface as a later optional download, if Phase 0 shows Apple's model isn't good enough.

### Apple Intelligence tags

- **When they're made:** after a link's preview is saved, the app asks `SystemLanguageModel(useCase: .contentTagging)` for 3–8 short tags. Structured output keeps them lowercase with no # symbols.
- **English:** the instructions ask for English tags whatever the text's language. Without that, Phase 0 got German and Spanish tags for about a dozen English pages.
- **Input:** title, site name, description and message text, trimmed to fit the model's context.
- **Pace:** one link at a time, only while the app is running.
- **Old links:** they're caught up gradually, the way `ChatStore` retries links missing a preview at launch.
- **Search:** tags are an indexed column, so keyword search matches them. A message found only by a tag has no word to highlight; it just flashes when jumped to.
- **When tagging fails:** the attempt is still recorded, so the app doesn't retry forever.
- **What's recorded with the tags:** the OS version they were made on. FoundationModels reports no model version (checked in the macOS 27 SDK), and Apple's model updates with the OS, so the OS version is the closest record of which model made them.

### Showing tags

- **Context menu:** a message's menu (long press on iPhone, right-click on the Mac) gets a Tags item while the tags tier is on.
- **Tags sheet:** it opens a sheet, on both platforms, listing that message's tags, or "Not tagged yet" before tagging reaches it.
- **No editing:** tags can't be added, removed or changed by hand. The sheet's Re-tag button asks the model again (see Re-tagging).
- **Tapping a tag** searches for it (proposed; to confirm once the sheet can be seen).

### Re-tagging

- **Never on its own:** each link is tagged once. A newer model, after an OS update, or a changed preview, after the reload button, doesn't re-tag anything by itself. Old tags keep working for search.
- **Re-tag All:** a Re-tag All Links… button on the tags row in Settings, while tags are on.
  - A confirmation says how many links it covers and that it runs only while the app is open.
  - Links are tagged again one at a time, with the row's progress line.
  - Each link keeps its old tags until its new ones arrive, so search never loses them. If the model refuses a link, its old tags stay.
  - The app stores when Re-tag All started (per device, like the settings), and any link last tagged before then is queued again. So it carries on after a relaunch.
- **Re-tag one link:** a Re-tag button in that message's Tags sheet.
  - It spins while the model works, then shows the new tags.
  - If the model refuses, the old tags stay and the sheet says Apple Intelligence couldn't tag this link.
  - It goes ahead of any queue: catching up old links, or Re-tag All.
- **Not available:** when Apple Intelligence can't run, both buttons are disabled with the same explanation as the Settings row.

## How results are shown

- **Stepping through the chat:** goes through every result, in the list's order: keyword matches newest first, then related ones, best first. The counter reads "N of M" over both, with 1 as the newest keyword match, and up/down work as now. A related result has no words to highlight, so it flashes when landed on, like a match found only by a tag.
- **A results list** with two sections:
  - **Matches:** keyword results, newest first, the order Telegram uses on both platforms.
  - **Related:** results by meaning, best match first, only when Smart Search is on.

### iPhone: copy Telegram-iOS's list mode

Telegram-iOS files (under `submodules/`):
- `TelegramUI/Sources/ChatTagSearchInputPanelNode.swift`: the mode toggle.
- `TelegramUI/Components/Chat/ChatInlineSearchResultsListComponent`: the list itself.
- `TelegramUI/Sources/ChatControllerNode.swift:3100-3549`: where the list is mounted.

Behavior:
- **Toggle:** the search panel gets "Show as List" / "Show as Chat". In list mode the counter reads "M messages". The toggle only shows when there are results.
- **Placement:** the list covers the chat on an opaque background. On the way in it fades over 0.2s, scales from 0.95 on a spring, and blurs in from 30; the chat behind scales to 0.95. It reverses on the way out.
- **Keyboard:** the list sits above the keyboard, and dragging it puts the keyboard away.
- **Rows:** date on the right, the preview's title or site, a small thumbnail (Telegram's inline thumbnails are 18pt), and a snippet with matches highlighted. When the first match is more than 24 characters in, the snippet starts about 12 characters before it with "…".
- **Tap:** jumps to the message centered, flashes it, and switches back to the chat view.
- **Paging:** more rows load when scrolling nears the end.

### Mac: copy TelegramSwift's dropdown

TelegramSwift files: `Telegram-Mac/ChatSearchHeader.swift`, `InputContextHelper.swift`, `ContextSearchMessageItem.swift`.

Behavior:
- **Placement and visibility:** the list drops down from the search field while the field has focus, and hides when focus leaves.
- **Height:** at most half the chat.
- **Rows:** 44pt, one line with "…", date on the right, newest first. TelegramSwift doesn't highlight matches in these rows; ours would, like iPhone.
- **Related:** related results get their own section below the matches, as on iPhone. TelegramSwift has nothing like it.
- **Selecting:** a click or Return jumps to the message and syncs the "N of M" position. The arrow keys move through the list, and Escape clears the selection.

## Database changes

Each tier gets its own migration, added in the phase that builds it, so Basic never carries unused tables.

- **Smart Search:** a new table `itemVector`, one row per message, holding the vector as 32-bit floats, the model ID and revision, and a hash of the text it was made from. If the preview changes the text, the vector is recomputed. Turning Smart Search off empties the table.
- **Tags:**
  - `item` gains `tags` (nullable), `tagsAttemptedAt` (nil until a try finishes, and set even if the model returned nothing, like `previewFetchedAt`), and `tagsOSVersion`, the OS version the tags were made on.
  - The search index gains a `tags` column. FTS5 tables can't gain a column, so the migration drops and recreates `itemSearch` and its triggers, then rebuilds it. The column stays empty unless the tier is on.
- **Share extension:** it runs migrations too (it can be first to open the database), so these must be fast: they move data but compute nothing.
- **Settings:** which tiers are on is stored per device (`UserDefaults`), not in the database.

## Phases

Each phase is built and tested before the next.

### Phase 0: test on real data (no app code)

- **Test set:** the links in `search-test-links.md`, 90 pages from popular sites, plus 20–30 queries the owner writes there, each with the link or links it should find.
- **Tool:** `Tools/SearchEval`, a command-line package on StatemonoKit, not part of either app. It reads the links and queries from `search-test-links.md` and keeps what it fetches in `Tools/SearchEval/Data/`, so every run is the same. From that folder:
  - `swift run SearchEval probe`: checks that Apple's English text model and Apple Intelligence work from the command line.
  - `swift run SearchEval snapshot`: fetches each link's preview once with the app's fetcher, into `snapshot.json`. It keeps what it has and fetches only new or missing links; `--refresh` fetches them all again.
  - `swift run SearchEval tag`: asks Apple Intelligence for tags, into `tags.json`, the way the app will (see Re-tagging). Each link is tagged once, and a refused link isn't retried. `--all` re-tags every link, and `--link <number>` re-tags one. Each entry records when it was tried and the OS version.
  - `swift run SearchEval eval`: recall for each tier, plus speed. For speed that matches the app, build it optimized: `swift run -c release -Xswiftc -enable-testing SearchEval eval`.
- **Recall:** the share of queries whose expected link lands first, in the top 5 and in the top 10. Measured for keywords today, then adding typo tolerance, tags, and related results.
- **Output:** how many related links to show, the typo limits, and whether Apple's vector model is good enough.

### Phase 0 results

Measured on 2026-09-29 on this Mac (macOS 27, Xcode 27). Recall below comes from 16 smoke queries Claude wrote to check the tool (`Tools/SearchEval/Data/smoke-queries.md`), so treat it as a first look. The owner's queries give the real numbers.

**What works from the command line**
- Apple's English text model and Apple Intelligence both answer a command-line process, so no scratch app is needed.
- Apple's English text model gives 512 numbers per vector and reads up to 256 tokens.
- It was already on this Mac, and the system runs it outside the app's process, so its download size couldn't be measured here. That waits for a device that doesn't have it yet (Phase 3).

**Links**
- All 90 have a preview. Nine were swapped because the fetcher got nothing: sites that block it (Stack Overflow, Allrecipes, IMDb, Goodreads, BBC News), Steam, and a swift.org page. Details are in `search-test-links.md`.
- Two of those are bugs in the app's fetcher, for later: Steam pages time out though `curl` loads them in about a second, and pages that redirect in the browser show "Redirecting…".

**Speed** (optimized build)

| Step | Time |
|---|---|
| A link's vector | 13ms, so a year of links (about 3,650) takes under a minute |
| A query's vector | 10ms |
| Comparing a query with 10,000 / 50,000 link vectors | 0.3ms / 2.7ms |
| Typo alternatives for a two-word query, over 880 / 10,000 / 50,000 words | 0.5ms / 9ms / 48ms |
| A link's tags | 1.1s median, so a year's backlog takes about an hour, done gradually |

- A plain scan of the vocabulary is fast enough: the test set's 90 links have 880 words, and a year of links should stay near 10,000. If it grows well past that, compare only words of similar length.

**Tags**
- Every link got 5 tags, occasionally 4, even with 3–8 allowed.
- Without "English" in the instructions, a dozen English pages got German or Spanish tags. The instructions now ask for English, and all tags came back English.
- The safety filter refused one harmless page, the Joel Test ("May contain unsafe content"), and refused it again when re-tagged on its own, so refusals are consistent. The plan already records failed attempts so they aren't retried forever.

**Smoke check: recall on 16 queries**

| Method | First | Top 5 | Results shown |
|---|---|---|---|
| Keywords (today) | 7 | 7 | 0.8 |
| + typo tolerance | 10 | 10 | 1.1 |
| + tags | 13 | 13 | 1.4 |
| + tags + 3 related (the plan's model, centered) | 13 | 16 | 4.4 |

- **Typo tolerance** found all 3 typo queries.
- **Tags** found 3 of the 6 queries that share no words with their link; the 3 related links found the other 3. Tags vary a little between runs: before a Re-tag All, tags found 2 and the combined result was 15.
- **Scores don't separate right from wrong:** the right link scored highest in only 4 of 16 queries, and the median right and best-wrong scores were 0.63 and 0.66. That's why the plan now shows a fixed 3 related links instead of using a cutoff.
- **Other options did worse:** Apple's older sentence model (`NLEmbedding.sentenceEmbedding`) and leaving the link out of the text both ranked worse than the plan's model.
- **Related links are mostly extra:** they helped only in the queries keywords missed. In the rest, all 3 were wrong links shown after the right one. See Open questions.
- **Small corpus:** with 90 links, a top 3 is easy to hit; with thousands it'll be harder. The owner's queries decide whether Apple's model is good enough.

**Next:** the owner writes 20–30 queries in `search-test-links.md`, then `swift run SearchEval eval` gives the real numbers.

### Phase 1: Basic

- **Scope:** typo tolerance and highlighting of the matched alternatives. No new tables, downloads or background work.
- **Code:** StatemonoKit, with tests for typos in finished words and in the word still being typed.
- **Ranking:** results merge from the start into one ranked list with a match kind (exact, prefix, typo, tag, related), so later tiers add sources without changing callers.

### Phase 2: Settings and the results list

- **Settings:** the gear button in place of ⋯, and the Settings sheet with the Smart Search section on iPhone and Mac, with every row and explanation above. Apple Intelligence tags shows its status even before the tier is built.
- **Results:** the list (Matches only at this point) on iPhone and Mac.

### Phase 3: Smart Search

- **Parts:** the opt-in download, the `Embedder` interface, preparing vectors with progress, related results in the list and in stepping, the Smart Search chip, and turning it off.
- **Release:** ship to TestFlight.

### Phase 4: Apple Intelligence tags

- **Scope:** iOS/macOS 26+ only, behind the availability checks. Includes the Tags menu item, the tags sheet, Re-tag for one link and Re-tag All.

### Later, each as its own opt-in step

- Understanding natural-language questions, for example turning "the YouTube video about Swift concurrency from last month" into a site, date range and keywords.
- Ask with citations.
- A larger bundled vector model, if Phase 0 says so.
- Core Spotlight indexing for system-wide search.

## Open questions

1. **When to show related results:** in the smoke check, the 3 related links helped only when keyword search found nothing, and otherwise added 3 wrong links after the right one. Proposed: the list's Related section always shows them, but up/down stepping includes them only when there are no keyword matches. To decide once the owner's queries have run.
