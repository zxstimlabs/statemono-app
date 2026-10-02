# Search plan: progressive search

Status: draft, updated 2026-10-02. Phase 4 (Apple Intelligence tags, and Apple first) is built and went to TestFlight as 0.1.17 (21). Phases 1 (typo tolerance), 2 (Settings and the results list) and 3 (Smart Search, with bge-small) are built. Phase 0 is done: on 29 queries Apple's text model found 1 of 7 meaning queries and bge-small found 6, so Smart Search uses bge-small (see Phase 0 results and Phase 3). Phase 3b, planned: test Spotlight's semantic search, Apple's model with nothing to download, as a replacement for bge-small.

## The idea

The app installs light and stays light:
- **Nothing extra at install:** no models are bundled, nothing downloads, and no work runs in the background.
- **Smarter search is opt-in:** people turn it on in a Smart Search section, in steps that match what they need. Each step says what it downloads and does.
- **Everything runs on the device.** Nothing is sent to a server. Smart Search downloads its model once; the tags use Apple's.
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
| Engine for meaning-based search | Apple's `NLContextualEmbedding` by default: no download, on wherever it runs (owner, 2026-10-01: Apple's on-device AI is the first-class option, even where it isn't the best). BAAI's bge-small-en-v1.5 is an optional "More accurate" download from Hugging Face. Both sit behind `TextEmbedder`. In Phase 0 Apple's model found 1 of 7 meaning queries and bge-small 6. Phase 3b (Spotlight) is paused |
| First on-device model feature | Tags at save time, on by default wherever Apple Intelligence is available (owner, 2026-10-01) |
| Minimum OS | Stays iOS 18 / macOS 15; model features only on iOS/macOS 26+ |
| Scale | 4–10 links a day, depending on the person: about 1,500–3,650 a year |
| Language | English only |
| Typo tolerance | Part of Basic, always on, no switch. It needs no download and runs on every device the app supports (see How a search works) |
| How results are shown | Both: stepping through the chat, plus a list |
| Related results | The list's Related section always shows them. Up/down stepping goes through them only when nothing matches by keyword (decided 2026-09-30 from Phase 0, for the owner to test) |
| Mac results list | TelegramSwift's dropdown under the search field |
| Tags | Used by search, and shown per message: long press (right-click on the Mac) → Tags opens a sheet with that message's tags. No editing. Re-tag All in Settings, and Re-tag for one link in its Tags sheet; nothing re-tags on its own |
| Settings | A gear button replaces the header's ⋯ on both platforms and opens Settings as a sheet, the same on both, with the Smart Search section |
| Prompting Smart Search | A chip in the search panel opens the Smart Search section |
| Test data | About 90 links to popular sites, chosen by Claude (`search-test-links.md`); the owner writes the queries |

## Tiers

| Tier | What it does | Downloads | Background work | Needs | Default |
|---|---|---|---|---|---|
| **Basic** | Keyword search as today, plus typo tolerance | None | None | Any supported OS (iOS 18 / macOS 15) | On |
| **Smart Search** | Related results by meaning, in the results list, and when stepping if nothing matches by keyword | bge-small from Hugging Face, one time, 133.7 MB | Makes a vector for each link, once, then one per new link | iOS 18 / macOS 15 | Off |
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
- **Off:** "Finds links by meaning, even without the same words. Downloads a search model once (133.7 MB)."
- **Downloading:** "Downloading the search model… 45%" with a progress bar.
- **Preparing:** "Preparing your links… 420 of 1,240" with a progress bar. This runs while the app is open.
- **Paused:** "Paused in Low Power Mode. 420 of 1,240 links ready."
- **Ready:** "On. 1,240 links ready."
- **Failed:** "Couldn't download the search model. Check your connection and try again." with a Try Again button. A model that downloaded but won't load is deleted first, so trying again downloads it afresh.

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
- **Smart Search's model is deleted too**, since the app downloaded it. The confirmation says how much that frees.
- **Apple Intelligence's model stays:** the system manages it, and there's no API to delete it. The section's footer says so.
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

- **Typo tolerance** (built in Phase 1: `SearchVocabulary` and `AppDatabase.search` in StatemonoKit's `Search/`):
  - Each query word is folded by the search tokenizer itself (lowercase, no accents), then compared against the index's vocabulary. `fts5vocab` over `itemSearch` holds exactly those folded terms.
  - **Only words that match nothing get alternatives.** A word that is, or starts, a word in the index is taken as spelled right. Otherwise "form" would also find "from", and since results are in date order, not by relevance, that noise would mix in. This rule was added while building Phase 1.
  - Allowed edits (Damerau–Levenshtein distance): 1 for words of 4–7 letters, 2 for 8 or more. Words of 3 letters or fewer must match exactly.
  - The last word may be unfinished, so it's also compared against the beginnings of index words of the same length: "levenhs" finds words starting with "levensh". Earlier words must be whole words within reach.
  - Each query word gets at most 10 alternatives, the most common first.
  - The FTS query becomes, for each word: `(word* OR alternative OR beginning* …)`, with every word still required.
- **Always on:** it needs only SQLite's FTS5, which every supported OS has, and a little Swift. There's nothing to download and no switch.
- **Highlighting:** bubbles highlight the typed words and the alternative words that matched. Both are already folded, so `SearchText` handles them as it does now.
- **Timing:** runs on every keystroke, debounced 0.2s as Telegram-iOS does (`ChatControllerUpdateSearch.swift:96`).
- **Cost:** a scan of the vocabulary, with no download and no background work. The vocabulary is kept in memory and read again only when items change (their count, latest edit or latest preview), which also catches writes from other processes.

### Smart Search: related matches, by meaning

- **Where it lives:** a `TextEmbedder` interface in StatemonoKit (model ID with its revision, dimension, text → vector of length 1). The implementation, `BertEmbedder`, runs bge-small with Accelerate (see Phase 3). Queries get bge's instruction, "Represent this sentence for searching relevant passages: ", first.
- **Not centered:** centering helped Apple's model in Phase 0 but made no difference to bge-small, so vectors are compared as they are.
- **What gets a vector:** preview title, site name, description and message text, trimmed to the model's limit.
- **Storage:** in SQLite, one vector per message (see Database changes). At 1.5 KB per link, a year of links takes about 6 MB.
- **Query:** the query gets its own vector. The app keeps all link vectors in memory and compares them with a dot product using Accelerate. Brute force is fine up to tens of thousands of links, which is years of saving at 4–10 a day.
- **What counts:** the 3 most similar links that keyword search didn't already match. There's no similarity cutoff: in Phase 0 right and wrong links scored about the same, so no cutoff could tell them apart. The test set's queries didn't change it: related links rarely found the right link at all.
- **When it runs:** as you type, with keyword search's 0.2s debounce. A query's vector took 10ms on this Mac in Phase 0; iPhone timing is checked in Phase 3.
- **Model files missing or failing to load:** the tier shows as failed in the section, and search behaves like Basic. Links still waiting for a vector aren't found by meaning yet.

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

- **Stepping through the chat:** goes through the keyword matches, newest first, as now. When nothing matches by keyword, it goes through the related results instead, best first, and "N of M" counts them. A related result has no words to highlight, so it flashes when landed on, like a match found only by a tag. In Phase 0 related links were wrong after a right keyword match in almost every query, so stepping skips them then.
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

- **Smart Search** (migration "v2 itemVector"): a table `itemVector`, one row per message, holding the vector as 32-bit floats, the model ID and revision, the SHA-256 of the text it was made from, and when it was made. If the preview or the text changes, the vector is made again. Turning Smart Search off empties the table.
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
  - `swift run SearchEval eval`: recall for each tier, plus speed. For speed that matches the app, build it optimized: `swift run -c release -Xswiftc -enable-testing SearchEval eval`. `--model <name>`, repeatable, compares only those models (`apple` for Apple's).
  - `swift run -c release -Xswiftc -enable-testing SearchEval try "<query>"`: searches the test links for one query, to test by hand. It prints today's matches (keywords, typos and tags), then the closest links by meaning for Apple's model and the app's bge-small (`app`), marking the 3 Smart Search would add. `--model` picks others.
  - `swift run -c release -Xswiftc -enable-testing SearchEval check`: checks the app's bge-small (`BertEmbedder`) against swift-embeddings' on every test link and query, and times it. `--download` also installs the model the way the app does, into a temporary folder.
  - Open models (`OpenModels.swift`) run with [swift-embeddings](https://github.com/jkrukowski/swift-embeddings) (MIT) on `MLTensor`, which iOS 18 and macOS 15 have. The first run downloads them from Hugging Face into `Data/Models` (about 1.4GB for all of them), which git ignores.
- **Recall:** the share of queries whose expected link lands first, in the top 5 and in the top 10. Measured for keywords today, then adding typo tolerance, tags, and related results.
- **Output:** how many related links to show, the typo limits, and whether Apple's vector model is good enough.

### Phase 0 results

Measured on 2026-09-29 on this Mac (macOS 27, Xcode 27). Recall below comes from 16 smoke queries Claude wrote to check the tool (`Tools/SearchEval/Data/smoke-queries.md`), so treat it as a first look. The test set's 29 queries, at the end of this section, give the real numbers.

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
| Typo alternatives for a two-word query, over 880 / 10,000 / 50,000 words | 0.3ms / 5ms / 27ms (the app's version, from Phase 1) |
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
- **Small corpus:** with 90 links, a top 3 is easy to hit; with thousands it'll be harder. The test set's queries measure whether Apple's model is good enough (below).

**Recall on the test set's 29 queries** (2026-09-30)

Claude wrote these at the owner's request, from each link's "What it is" and before reading its saved text; `search-test-links.md` says how. No query was changed after the run.

| Method | First | Top 5 | Results shown |
|---|---|---|---|
| Keywords | 16 | 16 | 0.7 |
| + typo tolerance (built) | 21 | 21 | 0.9 |
| + tags | 21 | 21 | 0.9 |
| + tags + 3 related (the plan's model, centered) | 21 | 22 | 3.9 |

- **Built search is solid:** it finds every exact (7), start-of-a-word (4), typo (5) and several-answers (3) query, first.
- **Site:** 2 of 3. "paul graham" finds nothing, because the site name is "paulgraham.com", one word; "paulgraham" would find both essays.
- **Meaning:** 0 of 7 by keywords or tags. The 3 related links found 1: "issue tracker" put Linear second.
- **Tags miss by one word:** every word must match, and tags got partway: Stoicism is tagged "philosophy" and "ancient" but not "greek", Obama's post "election" but not "night" or "tweet", and Ollama's text and tags matched all of "run ai models locally" but "locally".
- **Apple's model alone:** the right link came first in 0 of 29 queries and in the top 10 in 10. It never scored highest, and the median right score was 0.06 against 0.22 for the best wrong one (centered). No other variant reached more than 13 of 29 in the top 10.
- **Worse than the smoke check,** where related links found 3 of 6 meaning queries. Those were written after seeing the pages ("coffee drink" for Espresso); these weren't.
- **What it suggests:** Apple's model isn't good enough for Smart Search as planned. See Open questions.

**Open models on the same 29 queries** (2026-09-30)

Retrieval models from Hugging Face, the plan's "Swapping later" candidates, run the way the app would (swift-embeddings on `MLTensor`, CPU). Each gets the same text as Apple's (title, site, description and link), with the prefixes its model card asks for.

| Model | Download | Meaning found (of 7) | + 3 related: first / top 5 | Alone: first / top 10 | Per link / query on this Mac |
|---|---|---|---|---|---|
| Apple contextual (the plan), centered | system | 1 | 21 / 22 | 0 / 10 | 15 / 10ms |
| all-MiniLM-L6-v2 | 91MB | 6 | 26 / 28 | 22 / 27 | 32 / 20ms |
| bge-small-en-v1.5 | 133MB | 6 | 25 / 28 | 21 / 26 | 65 / 45ms |
| e5-small-v2 | 133MB | 5 | 26 / 27 | 22 / 25 | 63 / 41ms |
| gte-small | 67MB | 2 | 24 / 24 | 16 / 23 | 53 / 38ms |
| potion-retrieval-32M (static) | 129MB | 4 | 25 / 26 | 22 / 25 | 0.6 / 0.3ms |
| bge-base-en-v1.5 | 438MB | 5 | 26 / 27 | 24 / 27 | 102 / 61ms |
| nomic-embed-text-v1.5, centered | 547MB | 6 | 28 / 28 | 26 / 28 | 100 / 66ms |

- **Every open model but gte-small beats Apple's** by a wide margin. On their own, MiniLM and bge-small put the right link first in 21–22 of 29 queries; Apple's never did.
- **MiniLM and bge-small tie** here. On the 16 smoke queries bge-small came out slightly ahead (first 16 vs 14 of 16 with 3 related). bge-small is trained for search, with a query prefix; MiniLM for general similarity. Nomic is best but four times the download.
- **The one meaning query most missed** is "issue tracker": Linear's page says "product development", and only bge-small (7th, centered) came close. Apple's got it second, its only win.
- **Centering** barely changes the open models, so they don't need it.
- **Speed:** on the CPU. MLTensor's default, CPU and GPU, was about 6 times slower per link (190ms for both small models) with the same results, and asking for the Neural Engine ran no faster than the CPU. A year of links (3,650) takes about 4 minutes with bge-small and 2 with MiniLM on this Mac; iPhone is untested. The weights are 32-bit; 16-bit would halve the download.
- **Not measured:** EmbeddingGemma (swift-embeddings doesn't run it), and three models the package couldn't load (Snowflake Arctic Embed S, IBM Granite Embedding small R2, static-retrieval-mrl-en), listed in `OpenModels.swift`.

### Phase 1: Basic (built 2026-09-29)

- **Scope:** typo tolerance and highlighting of the matched alternatives. No new tables, downloads or background work.
- **Code:** StatemonoKit's `Search/`: `AppDatabase.search` returns `SearchResults`, newest first, each item with its `SearchMatch` (exact, prefix or typo; later tiers add tag and related), plus the folded words to highlight. `SearchTests` covers typos in finished words and in the word still being typed, spelled-right words, short words, result order and match kinds, and new words being found right after they're saved.
- **App:** `ChatSearch` waits 0.2s after a keystroke, like Telegram-iOS, and highlights the typed words and their alternatives. Results are newest first, so "1 of N" is the newest.
- **Checked** in the iPhone simulator: "rustdsk" finds and highlights RustDesk, and "overtke" finds overtake/TelegramSwift.
- **Phase 0 tool:** `SearchEval` now measures the app's own search instead of its prototype. On the smoke queries, typo tolerance still finds 10 of 16.

### Phase 2: Settings and the results list (built 2026-09-29)

- **Settings:** the gear button in place of ⋯, and the Settings sheet with the Smart Search section on iPhone and Mac, with every row and explanation above. Apple Intelligence tags shows its status even before the tier is built.
- **Results:** the list (Matches only at this point) on iPhone and Mac.

What was built (`App/Settings/SettingsView.swift`, `App/Chat/SearchResultsList.swift`, `SearchDropdown.swift`, `SearchSnippet.swift`):
- **Settings sheet:** a "Search" section with the three tier rows and a storage row, and a footer about turning steps off. The Smart Search and tags switches are shown but disabled, marked "Arrives in a later build", until Phases 3 and 4. The tags row reads Apple Intelligence's real availability. On the Mac, ⌘, and the app menu's Settings… open it (`SettingsCommands`).
- **FoundationModels** is weak-linked automatically, checked with `otool`, so iOS 18 and macOS 15 still launch.
- **iPhone list:**
  - The Telegram-iOS toggle, counter, rows (fonts, date rules, 18pt inline thumbnail, white matched words, snippet cut) and in/out animation, as researched from `ChatInlineSearchResultsListComponent` and `ChatListItem`.
  - Rows show the link's title where Telegram shows the author, and no avatar, since in Saved Messages that's always you.
- **Mac dropdown:** TelegramSwift's 44pt rows, cursor and current-row colors, arrow keys and slide-out, as researched from `InputContextHelper` and `ContextSearchMessageItem`.
- **Where it departs from Telegram:**
  - **iPhone arrows float over the chat.** The older/newer arrows moved out of the search panel into `FeedButtons`, as in Telegram-iOS (`ChatHistoryNavigationButtons`), where down scrolls to the bottom from the newest result. With the toggle, the panel had no room for them on a phone.
  - **The Mac dropdown is a floating glass card** under the search panel, as wide as the panel. TelegramSwift's spans the chat under an opaque header; the app's header floats.
  - **Return opens the cursor's row on the Mac.** TelegramSwift only acts on the selected row, which looks like a bug.
  - **Picking a row makes it the current result on iPhone too**, so "N of M" and the arrows carry on from it. Telegram-iOS leaves the current result where it was.

### Phase 3: Smart Search (built 2026-09-30)

- **Parts:** the opt-in download, the `TextEmbedder` interface, preparing vectors with progress, related results in the list and in stepping, the Smart Search chip, and turning it off.
- **Release:** ship to TestFlight.

What was built (StatemonoKit's `SmartSearch/`, `App/Chat/SmartSearch.swift`, `ChatSearch`, `SearchBar`, `SearchResultsList`, `SearchDropdown`, `SettingsView`):
- **The model, run by the app itself.** `BertEmbedder` is bge-small's forward pass on the CPU with Accelerate (`cblas_sgemm`), with BERT's uncased WordPiece tokenizer (`WordPieceTokenizer`) and a reader for `.safetensors` that maps the file instead of loading it (`Safetensors`). swift-embeddings, which Phase 0 measured with, would have brought about ten packages into the app, a 40MB prebuilt library among them.
  - **Checked** against swift-embeddings on all 90 links, the 45 queries and a few odd strings (`SearchEval check`): the same tokens, and vectors with a cosine similarity of at least 0.9999. The one exception is text over 512 tokens, where swift-embeddings drops the final [SEP] and the app keeps it, as Hugging Face's tokenizer does. `eval` gives the app's version the same recall as the reference.
  - **Speed** on this Mac: 9ms per link, 5ms per query, about 7 times faster than swift-embeddings on `MLTensor`. iPhone speed is to be seen on a device.
- **The download** (`SearchModelStore`): `config.json`, `vocab.txt` and `model.safetensors` from `huggingface.co/BAAI/bge-small-en-v1.5`, pinned to revision `5c38ec7`, each checked against its SHA-256. They go to Application Support/<bundle id>/Models, excluded from backups. A download task with its own delegate reports progress. It took about 6 seconds here.
- **Preparing** (`SmartSearch`): while the app is open, 16 links at a time, newest first, off the main thread. Links wait for their preview. A database observation catches new, edited and deleted links and saved previews, and Low Power Mode pauses it.
- **Searching:** the query's vector is compared with every link's in memory (`AppDatabase.relatedItems`, one matrix-vector product), and the 3 best that keyword search didn't find are added. The vectors are read again only when they or the items change.
- **Stepping:** through the keyword matches, or the related links when nothing matched, with "1 of 3 related". A related row picked from the list while there are matches jumps without becoming the current result.
- **The list and dropdown** show the related links under a Related header, after the matches.
- **The chip** shows in the search panel while Smart Search is off and nothing was found, and opens Settings.
- **Checked** in the iPhone simulator and a Mac harness, with the 90 test links: the chip, the download and preparing (90 links), "graduation speech" finding Steve Jobs's commencement address through the arrows and the list, a related row opening while there's a match, and turning off deleting the model, the vectors and the setting.

### Phase 3b: test Spotlight's semantic search (planned, no app code)

The owner asked on 2026-10-01 for an option from Apple, so Smart Search wouldn't download a model from Hugging Face. Apple's other text models lost to bge-small in Phase 0. Core Spotlight's semantic search is a different one, built for search, and it wasn't measured. If it isn't good enough, the owner would combine Phases 3 and 4 instead.

**What the docs and SDKs say** (iOS 27 and macOS 27 SDKs, the WWDC24 session "Support semantic search with Core Spotlight", developer forums):
- **How it works:** the app indexes each link as a `CSSearchableItem` with `title` and `textContent`, which go into the semantic index. Before search shows, the app calls `CSUserQuery.prepare()`. A search is a `CSUserQuery` with a `CSUserQueryContext`, read through `responses`.
  - `enableRankedResults` turns on Apple's ranking, and the app sorts with `compareByRank`. `maxRankedResultCount` defaults to 100.
  - `disableSemanticSearch` gives keyword-only results.
- **No scores:** Apple returns a ranking, not similarity scores. Smart Search already uses no cutoff, so it would take the best 3 that keyword search missed, as now.
- **Apple's model:** it downloads to the device and runs in the app's process (WWDC24). Nothing in the docs says which devices or OS versions get it, or whether it needs Apple Intelligence. The API exists from iOS 18 and macOS 15, the app's minimum.
- **System search:** items indexed this way also show up in the device's Spotlight. App Intents' `IndexedEntity` has `hideInSpotlight` (iOS 18.4, macOS 15.4), indexed with `CSSearchableIndex.indexAppEntities`. The docs don't say whether `CSUserQuery` still finds hidden items.
- **Risk: it may not work.** In a forum thread (developer.apple.com/forums/thread/793867), developers report that from iOS 18 through the iOS 26 beta and macOS 26.2 beta, semantic search returned the same results as keyword search. Their logs said "Text embedding generation timeout (timeout=100ms)".
  - One developer got it working in April 2026 by sending a throwaway first query. They also said `disableSemanticSearch` behaved reversed.
  - No one from Apple answered. The iOS 27 SDK adds only a Swift wrapper for item attributes, nothing for semantic search.

**The test:**
- **Tool:** a small Mac app, `Tools/SpotlightEval` (xcodegen, its own bundle ID). Spotlight indexes only for an app, so `SearchEval` can't do this from the command line. It reuses SearchEval's `Data/snapshot.json` (the 90 links' saved previews) and the 29 queries in `search-test-links.md`.
- **Index:** the 90 links, with the same text the other models got (title, site, description and link). Two ways: plain `CSSearchableItem`s, and `IndexedEntity`s with `hideInSpotlight`. Time how long until search finds them.
- **Search:** each query four ways: semantic on and off, each with and without a throwaway first query. Keep the top 10.
- **Score** the way Phase 0 did:
  - How many of the 7 meaning queries the 3 related links find.
  - How often the right link comes first, and how often it's in the top 10, on its own.
  - bge-small's numbers are the bar: 6 of 7, first in 21 of 29, top 10 in 26.
- **Checks:**
  - Semantic results must differ from keyword-only, or semantic search isn't running.
  - `CSUserQuery` must find hidden entities. The owner checks that the system's Spotlight doesn't show them by typing a test link's title.
- **Afterwards:** the app deletes its index, so nothing stays in the owner's Spotlight.
- **Where:** this Mac first (macOS 27). The iPhone only if the Mac passes: the simulator may not have Apple's model, and a device build needs the iPhone registered with the team.
- **Decision:** the owner's, from the numbers.
  - If Spotlight matches bge-small, Smart Search switches to it and stops downloading. Devices without it would need bge-small or no Smart Search.
  - If not, Phases 3 and 4 are combined, as the owner said. Tags alone don't find meaning: in Phase 0 they added none of the 7 meaning queries (Recall on the test set's 29 queries, "+ tags"), so combining means bge-small plus tags.

### Phase 4: Apple Intelligence tags, and Apple first (2026-10-01)

- **Scope:** iOS/macOS 26+ only, behind the availability checks. Includes the Tags menu item, the tags sheet, Re-tag for one link and Re-tag All.
- **Apple first** (owner, 2026-10-01: "lean more into on-device AI native from Apple, even if it's not the best, as first-class"):
  - **Tags** are on by default wherever Apple Intelligence is available, with a switch to turn them off.
  - **Smart Search** is on by default, running Apple's `NLContextualEmbedding`, which the system provides (no download). Vectors are compared centered, as Phase 0 found best for it.
  - **More accurate Smart Search** is an optional switch that downloads bge-small (133.7 MB) and uses it instead. Devices that already downloaded it keep it on.
  - **Settings › Search order:** Basic, Smart Search (Apple), More accurate (bge-small), Apple Intelligence tags, Storage.

What was built (2026-10-02):
- **StatemonoKit:**
  - Migration `v4 tags`: `item` gains `tags`, `tagsAttemptedAt` and `tagsOSVersion`, and `itemSearch` is recreated with a `tags` column.
  - `AppDatabase+Tags`: the queue, saving, Re-tag All, removal and storage size.
  - `SearchMatch.tag` for results found only through tags.
  - `AppleEmbedder`, for `NLContextualEmbedding`.
  - `relatedItems(…centered:)`.
- **App:**
  - `AppleIntelligenceTags`, the tagging engine.
  - `SmartSearch`, with Apple's model by default and bge-small as "More accurate".
  - Settings › Search's new rows and confirmations.
  - The Tags menu item, on both menus.
  - `TagsSheet`.
- **Tested:**
  - Unit tests (`TagsTests`): links waiting for previews, tag matches, refusals, Re-tag All, removal, centered ranking. 63 tests pass.
  - The migration on a copy of the 90-link database: half a second, with the index and its triggers rebuilt.
  - **Mac harness, with both of Apple's models available:**
    - Defaults on: 52 links tagged in 80 seconds and all 90 given vectors by Apple's model.
    - "note taking" found Obsidian through its tag "note-taking" alone.
    - The Tags sheet opened from the menu, and choosing "ai" searched for it.
  - **iPhone simulator:** neither model exists there. Smart Search gave up after 90 seconds with Try Again, and tags showed that they were waiting for Apple Intelligence.
- **Seen in testing:** Apple's model's related links are loose, as Phase 0 predicted. For "note taking" they were GitHub's Swift page, PocketBase and Linear.

### Later, each as its own opt-in step

- Understanding natural-language questions, for example turning "the YouTube video about Swift concurrency from last month" into a site, date range and keywords.
- Ask with citations.
- A larger bundled vector model, if Phase 0 says so.
- Core Spotlight indexing for system-wide search.

## Open questions

1. **When to show related results:** decided 2026-09-30, as proposed, for the owner to test: the list's Related section always shows them, and up/down stepping includes them only when there are no keyword matches (see How results are shown). In Phase 0 the related links helped only when keyword search found nothing, and otherwise added wrong links after the right one.
2. **Smart Search's model:** decided 2026-09-30, when the owner asked for Smart Search to be built with it: bge-small, downloaded from Hugging Face (Phase 3). Still open:
   - 16-bit weights would halve the download to about 67MB, but need a copy the app's owner hosts, since the repository has only 32-bit ones. `eval` would check they rank the same.
   - Speed on an iPhone.
