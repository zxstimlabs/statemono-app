# Statemono

Telegram "Saved Messages" for links. Share or paste links, and they appear as chat bubbles with rich previews. Everything is full-text searchable. One SwiftUI codebase for iPhone and Mac.

## Setup

```sh
brew install xcodegen   # once
xcodegen generate       # creates Statemono.xcodeproj from project.yml
open Statemono.xcodeproj
```

The `.xcodeproj` is generated and not committed. Edit `project.yml` instead.

Package tests:

```sh
cd Packages/StatemonoKit && swift test
```

## Layout

- `project.yml`: XcodeGen spec with two targets, `Statemono-iOS` and `Statemono-macOS`. They share `App/`.
- `App/`: SwiftUI app.
- `Packages/StatemonoKit/`: all non-UI logic, with tests.
