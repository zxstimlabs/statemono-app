# Search test links

For Phase 0 of `search-plan.md`. Claude chose the links on 2026-09-29; the owner writes the queries.

- **Fetched 2026-09-29:** every link's preview was fetched with the app's own fetcher and kept in `Tools/SearchEval/Data/snapshot.json`, so every run searches the same text. All 90 have one.
- **Swapped:** nine links gave no preview and were replaced. Stack Overflow and Allrecipes refuse the fetcher (403), IMDb and Goodreads serve bot checks (Goodreads only on some tries), and BBC News timed out, so they moved to other sites. Steam timed out in the app's fetcher, though `curl` loads it in about a second; that's a preview bug for later, and the games moved to their official sites. Swift.org's documentation page redirects in the browser, which the fetcher doesn't follow, so it showed only "Redirecting…"; it became Hacking with Swift.
- **Neighbors on purpose:** several links share a site or a topic (Apple's laptops, two TED talks, the Beatles on Wikipedia and Spotify, Tokyo and a Japan guide, Tailscale's blog and home page), so a query has to pick the right one among similar links.
- **Weak previews, kept on purpose:** Reddit and Hacker News give only their names, the Rust book only its title, ChatGPT no title, and the Hades page describes the studio rather than the game. Saved links look like this too.
- **X posts** go through fxtwitter, as in the app. Add X posts you've saved yourself; these four are the only post IDs Claude knows for sure.

## Queries

Write 20–30. Each row names the link numbers it should find, separated by commas. Then, from `Tools/SearchEval`, run `swift run SearchEval eval`. Write a few of each kind, so each tier can be measured:
- **Exact:** words that appear in the link's title or description.
- **Start of a word:** a word typed partway, like "photog" for photography.
- **Typo:** a misspelled word, like "restaraunt".
- **Meaning:** none of the query's words appear in the link, like "place to stay" for a hotel page.
- **Site:** just the site's name, like "wikipedia".
- **Several answers:** more than one link is right.

| Query | Should find | Kind |
|---|---|---|
| | | |

## Links

### Apple

| # | Link | What it is |
|---|---|---|
| 1 | https://www.apple.com/iphone/ | iPhone lineup |
| 2 | https://www.apple.com/macbook-air/ | MacBook Air |
| 3 | https://www.apple.com/macbook-pro/ | MacBook Pro |
| 4 | https://www.apple.com/apple-vision-pro/ | Apple Vision Pro headset |
| 5 | https://www.apple.com/airpods-pro/ | AirPods Pro |
| 6 | https://www.apple.com/watch/ | Apple Watch lineup |
| 7 | https://www.apple.com/privacy/ | Apple's privacy page |
| 8 | https://www.apple.com/newsroom/ | Apple Newsroom |
| 9 | https://developer.apple.com/documentation/swiftui | SwiftUI documentation |
| 10 | https://developer.apple.com/documentation/foundationmodels | Foundation Models documentation |
| 11 | https://developer.apple.com/design/human-interface-guidelines/ | Human Interface Guidelines |
| 12 | https://developer.apple.com/wwdc25/ | WWDC (the page now shows WWDC26) |

### Wikipedia

| # | Link | What it is |
|---|---|---|
| 13 | https://en.wikipedia.org/wiki/SQLite | SQLite |
| 14 | https://en.wikipedia.org/wiki/Telegram_(software) | Telegram |
| 15 | https://en.wikipedia.org/wiki/Swift_(programming_language) | Swift |
| 16 | https://en.wikipedia.org/wiki/Levenshtein_distance | Levenshtein distance |
| 17 | https://en.wikipedia.org/wiki/Espresso | Espresso |
| 18 | https://en.wikipedia.org/wiki/Sourdough | Sourdough |
| 19 | https://en.wikipedia.org/wiki/Mount_Everest | Mount Everest |
| 20 | https://en.wikipedia.org/wiki/Great_Barrier_Reef | Great Barrier Reef |
| 21 | https://en.wikipedia.org/wiki/Photosynthesis | Photosynthesis |
| 22 | https://en.wikipedia.org/wiki/Black_hole | Black hole |
| 23 | https://en.wikipedia.org/wiki/The_Beatles | The Beatles |
| 24 | https://en.wikipedia.org/wiki/Marathon | Marathon |
| 25 | https://en.wikipedia.org/wiki/Stoicism | Stoicism |
| 26 | https://en.wikipedia.org/wiki/Bitcoin | Bitcoin |
| 27 | https://en.wikipedia.org/wiki/Large_language_model | Large language model |
| 28 | https://en.wikipedia.org/wiki/Tokyo | Tokyo |
| 29 | https://en.wikipedia.org/wiki/Iceland | Iceland |
| 30 | https://en.wikipedia.org/wiki/Pomodoro_Technique | Pomodoro Technique |
| 31 | https://en.wikipedia.org/wiki/Mediterranean_diet | Mediterranean diet |
| 32 | https://en.wikipedia.org/wiki/James_Webb_Space_Telescope | James Webb Space Telescope |

### X

| # | Link | What it is |
|---|---|---|
| 33 | https://x.com/jack/status/20 | Jack Dorsey: "just setting up my twttr" |
| 34 | https://x.com/BarackObama/status/266031293945503744 | Barack Obama: "Four more years." |
| 35 | https://x.com/TheEllenShow/status/440322224407314432 | Ellen DeGeneres's Oscars group selfie |
| 36 | https://x.com/elonmusk/status/1585841080431321088 | Elon Musk: "the bird is freed" |

### YouTube

| # | Link | What it is |
|---|---|---|
| 37 | https://www.youtube.com/watch?v=dQw4w9WgXcQ | Rick Astley, "Never Gonna Give You Up" |
| 38 | https://www.youtube.com/watch?v=jNQXAC9IVRw | "Me at the zoo", the first YouTube video (its description is now about microplastics) |
| 39 | https://www.youtube.com/watch?v=9bZkp7q19f0 | PSY, "Gangnam Style" |
| 40 | https://www.youtube.com/watch?v=kJQP7kiw5Fk | Luis Fonsi, "Despacito" |
| 41 | https://www.youtube.com/watch?v=UF8uR6Z6KLc | Steve Jobs's Stanford commencement speech |
| 42 | https://www.youtube.com/watch?v=arj7oStGLkU | Tim Urban's TED talk on procrastination |

### GitHub

| # | Link | What it is |
|---|---|---|
| 43 | https://github.com/groue/GRDB.swift | GRDB, SQLite for Swift |
| 44 | https://github.com/overtake/TelegramSwift | Telegram for macOS |
| 45 | https://github.com/TelegramMessenger/Telegram-iOS | Telegram for iOS |
| 46 | https://github.com/swiftlang/swift | The Swift compiler |
| 47 | https://github.com/pointfreeco/swift-composable-architecture | The Composable Architecture |
| 48 | https://github.com/ollama/ollama | Ollama, local LLMs |
| 49 | https://github.com/ggml-org/llama.cpp | llama.cpp |
| 50 | https://github.com/sqlite/sqlite | SQLite's source mirror |
| 51 | https://github.com/torvalds/linux | The Linux kernel |
| 52 | https://github.com/basecamp/omarchy | Omarchy |
| 53 | https://github.com/hyprwm/Hyprland | Hyprland |
| 54 | https://github.com/pocketbase/pocketbase | PocketBase |

### Developer reading

| # | Link | What it is |
|---|---|---|
| 55 | https://www.sqlite.org/fts5.html | SQLite's FTS5 documentation |
| 56 | https://developer.mozilla.org/en-US/docs/Web/JavaScript | MDN's JavaScript guide |
| 57 | https://doc.rust-lang.org/book/ | The Rust Programming Language, the Rust book |
| 58 | https://martinfowler.com/articles/microservices.html | Martin Fowler, "Microservices" |
| 59 | https://paulgraham.com/avg.html | Paul Graham, "Beating the Averages" |
| 60 | https://paulgraham.com/startupideas.html | Paul Graham, "How to Get Startup Ideas" |
| 61 | https://www.joelonsoftware.com/2000/08/09/the-joel-test-12-steps-to-better-code/ | The Joel Test |
| 62 | https://www.hackingwithswift.com/100/swiftui | Hacking with Swift: 100 Days of SwiftUI |
| 63 | https://tailscale.com/blog/tailscale-rustdesk-remote-desktop-access | Tailscale blog: remote desktops with RustDesk |
| 64 | https://news.ycombinator.com/ | Hacker News front page |

### Movies, music, games, books, news

| # | Link | What it is |
|---|---|---|
| 65 | https://letterboxd.com/film/the-shawshank-redemption/ | The Shawshank Redemption on Letterboxd |
| 66 | https://letterboxd.com/film/interstellar/ | Interstellar on Letterboxd |
| 67 | https://www.netflix.com/title/80057281 | Stranger Things on Netflix |
| 68 | https://open.spotify.com/artist/3WrFJ7ztbogyGnTHbHJFl2 | The Beatles on Spotify |
| 69 | https://www.thinkwithportals.com/ | Portal 2's official site |
| 70 | https://supergiantgames.com/games/hades/ | Hades on Supergiant Games' site (the preview describes the studio) |
| 71 | https://en.wikipedia.org/wiki/The_Hobbit | The Hobbit, on Wikipedia |
| 72 | https://www.ted.com/talks/sir_ken_robinson_do_schools_kill_creativity | Ken Robinson's TED talk, "Do schools kill creativity?" |
| 73 | https://www.nytimes.com/games/wordle/index.html | Wordle |
| 74 | https://www.theguardian.com/international | The Guardian, international edition |

### Food, travel, home, fitness

| # | Link | What it is |
|---|---|---|
| 75 | https://cooking.nytimes.com/recipes/1015819-chocolate-chip-cookies | NYT Cooking: chocolate chip cookies |
| 76 | https://www.ikea.com/us/en/p/billy-bookcase-white-00263850/ | IKEA BILLY bookcase |
| 77 | https://www.nps.gov/yose/index.htm | Yosemite National Park |
| 78 | https://www.lonelyplanet.com/japan | Lonely Planet's Japan guide |
| 79 | https://www.airbnb.com/ | Airbnb |
| 80 | https://www.reddit.com/r/swift/ | r/swift |
| 81 | https://www.duolingo.com/ | Duolingo |
| 82 | https://www.strava.com/ | Strava |

### Tools and apps

| # | Link | What it is |
|---|---|---|
| 83 | https://www.figma.com/ | Figma |
| 84 | https://linear.app/ | Linear |
| 85 | https://www.raycast.com/ | Raycast |
| 86 | https://obsidian.md/ | Obsidian |
| 87 | https://www.notion.com/ | Notion |
| 88 | https://www.anthropic.com/ | Anthropic |
| 89 | https://chatgpt.com/ | ChatGPT |
| 90 | https://tailscale.com/ | Tailscale's home page |
