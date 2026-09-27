# Statemono

Telegram "Saved Messages" for links. Share or paste links, and they appear as chat bubbles with rich previews. Everything is full-text searchable. One SwiftUI codebase for iPhone and Mac.

## Status

Early. The Mac app's chat interface is built and runs on sample data. The database, link previews, share extension, and sync are still to come.

What works on macOS today:

- A feed of chat bubbles with link previews, modeled on Telegram's night theme.
- The composer: type or paste, then press Return to send. The feed slides up the way Telegram's does.
- In-chat search (⌘F): jump between matches with Return or ▲/▼, jump to a date, and close with Escape. Matching ignores case and tone marks, and treats đ as d.
- The attach menu. Its items are placeholders.

Messages you send are kept in memory only for now.

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
  - `Chat/`: feed, bubbles, composer, attach menu, and search. `Theme.swift` holds the colors and sizes. Mac-only pieces (`FeedScroller`, `TrafficLightsAligner`) are wrapped in `#if os(macOS)`.
  - `SampleData/`: mock messages that the feed shows until it reads from the database.
  - `Assets.xcassets/`: the app icon, generated from `Design/`.
- `Packages/StatemonoKit/`: all non-UI logic (model, database, search, metadata, sync), with tests.
- `Design/`: source artwork, such as the app icon logo.
