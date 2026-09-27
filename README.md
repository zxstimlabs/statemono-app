# Statemono

Telegram "Saved Messages" for links. Share or paste links, and they appear as chat bubbles with rich previews. Everything is full-text searchable. One SwiftUI codebase for iPhone and Mac.

## Status

Early. The Mac app works end to end: messages and link previews are saved in a local SQLite database, and search covers all of history. The share extension and sync are still to come.

What works on macOS today:

- A feed of chat bubbles with link previews, modeled on Telegram's night theme.
- The composer: type or paste, then press Return to send. The feed slides up the way Telegram's does.
- Link previews, fetched on your Mac when you send a link: site, title, description, and image. X posts come through the [fxtwitter](https://github.com/FixTweet/FxTwitter) API, and other sites from their OpenGraph and Twitter card tags. Fetching contacts the linked site, or fxtwitter for X links, directly from your device. Preview text, plus a tiny blurred placeholder, is kept with the message. Images are downloaded once, when they first scroll into view, and then kept on disk, as Telegram does. They live in `~/Library/Application Support/com.statemono/Media`, and a cleanup screen is planned. The ↻ in a link bubble's corner reloads its preview.
- In-chat search over all of history from the search field in the header (click it, or press ⌘F to open and close it), using SQLite full-text search: jump between matches with Return or ▲/▼, jump to a date, and close with Escape. Each word matches the start of a word, ignoring case and tone marks, and đ matches d.
- A message's context menu, like Telegram's: right-click, two-finger tap, or Control-click anywhere on a message's row. Copy Text copies the message, and Delete asks first, then removes it from the feed and search. The other items (Reply, Translate, Edit, Pin, Forward, Select) are placeholders.
- The attach menu. Its items are placeholders.

Messages are stored in `~/Library/Application Support/com.statemono/statemono.sqlite`. The feed loads 50 at a time and loads more as you scroll up.

## Requirements

- macOS 15 or later to run the Mac app. The iPhone app targets iOS 18.
- Xcode 16 or later. The project is built with Xcode 26.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Setup

```sh
brew install xcodegen   # once
xcodegen generate       # creates Statemono.xcodeproj from project.yml
open Statemono.xcodeproj
```

Run the `Statemono-macOS` or `Statemono-iOS` scheme.

The `.xcodeproj` is generated and not committed. Edit `project.yml` instead, and run `xcodegen generate` again after adding or removing files.

Package tests:

```sh
cd Packages/StatemonoKit && swift test
```

## Layout

- `project.yml`: XcodeGen spec with two targets, `Statemono-iOS` and `Statemono-macOS`. They share `App/`.
- `App/`: the SwiftUI app.
  - `Chat/`: feed, bubbles, composer, menus, and search. `Theme.swift` holds the colors and sizes. Mac-only pieces (`FeedScroller`, `TrafficLightsAligner`, `WindowEventMonitor`) are wrapped in `#if os(macOS)`.
  - `Assets.xcassets/`: the app icon, generated from `Design/`.
- `Packages/StatemonoKit/`: all non-UI logic, with tests.
  - `Database/`: the SQLite database (GRDB): messages, link previews, the image index, and full-text search with a đ→d tokenizer.
  - `LinkPreviews/`: fetching previews (fxtwitter for X, OpenGraph for websites) and the on-disk image cache.
- `Design/`: source artwork, such as the app icon logo.
