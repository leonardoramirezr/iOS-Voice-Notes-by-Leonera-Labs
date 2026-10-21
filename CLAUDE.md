# CLAUDE.md

## Rules

- Whenever you finish a task and write a summary of the implemented changes, include the name of the build that
  contains those changes, for example `build-30-1bca82e` (branch builds are `build-<run_number>-<sha7>`; builds
  of `main` are `0.x.0`). Get it from the GitHub Actions run of the pushed commit.
- Code comments, Markdown files and every identifier (types, functions, properties, variables, files) must be in
  English. User-facing strings are localized (English and Spanish).

## Project

- SwiftUI iOS 26 app generated with XcodeGen (`project.yml`); the `.xcodeproj` is not committed.
- `App/`: SwiftUI screens and Apple-framework glue. Every UI string goes through `App/Support/L10n.swift`
  (`String(localized: "key", defaultValue: "English")`) and must have English and Spanish values in
  `App/Resources/Localizable.xcstrings`; `scripts/check_strings.py` enforces it in CI.
- `Packages/VoiceNotesCore`: Foundation-only logic (Swift 6 language mode). It must keep building on Linux.
- `Packages/VoiceNotesSync`: Core Data + Simperium 1.9.2 (Swift 5 language mode). Its tests run only on macOS.
- The Simplenote model must stay compatible with the official app: entity `Note` (bucket name), members
  `content`, `creationDate`, `modificationDate`, `deleted`, `owner`, `publishURL`, `shareURL`, `systemTags`,
  `tags` (`jsonlist`). Never write nil to synced members and never declare a Swift property named `deleted`.
- Simperium runs in token mode (`authenticate(withAppID:token:)`); the session lives in the Keychain.

## Commands

```sh
python3 -m unittest discover -s scripts/tests
python3 scripts/check_strings.py
swift test --package-path Packages/VoiceNotesCore
swift test --package-path Packages/VoiceNotesSync   # macOS only
xcodegen generate                                   # macOS only
```

There is no local iOS compiler in Linux containers: the GitHub Actions build (`.github/workflows/build.yml`) is
the iOS compiler. Verify new Apple APIs against developer.apple.com before using them.
