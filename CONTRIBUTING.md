# Contributing to Quackie Chan

Thanks for wanting to make the duck better! Bug reports, ideas, new ducks, new moves, funnier lines: all welcome.

## Getting set up

1. Install Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) if you'll add files.
2. `open QuackieChan.xcodeproj`, choose your own team under **Signing & Capabilities** (or run `./scripts/build.sh`, which signs ad hoc), and run.
3. Run the tests with ⌘U, or `xcodebuild -project QuackieChan.xcodeproj -scheme QuackieChan test`.

The project file is generated from `project.yml`. If you add, move or delete files, run `xcodegen generate` and commit the regenerated project with your change.

## Easy first contributions

- **Lines.** Every personality's lines are in `QuackieChan/Brain/Lines.swift`. Funnier is better; mean about people's bodies, identity or health is never okay.
- **A new hat or duck.** Hats are painted in `paintHat` in `QuackieChan/Duck/Sprites.swift`; ducks are listed in `DuckSkin.all`. Run `./scripts/make-icons.sh` to see them all in `docs/images/ducks.png`.
- **A new move.** Add a case to `Duck.Activity` and describe its pose in `Duck.step(by:)`. Start it from `DuckWindow` (antics) or `Director` (goals).
- **More sites.** Shops, social media and video sites are listed in `Place` in `QuackieChan/Brain/Goals.swift`.

## Ground rules

- **Privacy first.** Nothing may leave the Mac except a model download the user asked for. No analytics, no telemetry, no cloud APIs. Screenshots and screen text stay in memory.
- **Light.** The duck should cost next to nothing when it's just standing there. Avoid timers that run when nothing's happening, and heavy work on the main thread.
- **Harmless.** The duck may threaten, but anything it actually does must be opt-in and undoable. It never quits apps, deletes, buys or types.
- **Match the style.** Plain Swift and SwiftUI, small files, comments that explain *why*. Write user-facing text in plain, friendly English.

## Pull requests

- Keep each one to one thing, and say what it changes and how you tried it.
- Include a screenshot or GIF for anything visible.
- Make sure it builds and the tests pass.

By contributing you agree that your work is shared under the project's [MIT License](LICENSE). Please follow the [code of conduct](CODE_OF_CONDUCT.md).
