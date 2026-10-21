# Voice Notes by Leonera Labs

A SwiftUI iPhone app that edits your [Simplenote](https://simplenote.com) notes by voice.

Say *"En la nota de muebles añade: en Mercado Basco de Quiroga compró sus muebles Brandon"* and the app
transcribes it, works out which note to change and how, shows you the change as a highlighted diff, and saves
it to Simplenote when you confirm.

## Features

- **Simplenote sync** with the same engine as the official Simplenote iOS app:
  [Simperium iOS](https://github.com/Simperium/simperium-ios) 1.9.2 and the same `Note` bucket and members.
  Notes are stored locally in SQLite and synced in the background, including offline edits.
- **Email code login**, the default login of the official app: enter your email, then the 6-character code
  Simplenote sends you. No password or API key is needed.
- **Notes list** with pinned notes first, search, pin and trash, plus a plain-text editor.
- **Floating Liquid Glass menu** (iOS 26): Search, Add manually, Add via audio.
- **Voice commands** powered by [Groq](https://groq.com):
  1. Speech is transcribed with Whisper (`whisper-large-v3` by default).
  2. A Groq LLM (`openai/gpt-oss-120b` by default) finds the target note(s) and plans the edit steps
     (append, insert, replace, delete, mark as done). The steps are applied locally and deterministically.
  3. If the note or the change is missing, the app says what is missing, reads it aloud, and lets you add
     more audio.
  4. A review screen shows the note title (pinned while scrolling) and a single unified diff (green = added,
     red = removed), opened at the first change, with **Save**, **Cancel** and **Add instructions**.
- **Settings**: Groq API key (stored in the Keychain), models, transcription language, spoken replies,
  account and sign out, version and build name.
- English and Spanish interface, following the iPhone language.

## Requirements

- iPhone with iOS 26 or later.
- A Simplenote account.
- A Groq API key (<https://console.groq.com/keys>) for voice commands. The free tier works; it allows about
  8K tokens per minute for the LLM, so very fast consecutive commands may need to wait a few seconds.

## Install on an iPhone

Every push builds an Ad Hoc IPA and publishes it on GitHub Pages:
<https://leonardoramirezr.github.io/iOS-Voice-Notes-by-Leonera-Labs/>

1. Open the page in **Safari** on the iPhone.
2. Tap **Install latest stable** (or **Install** next to any build) and confirm.
3. The app appears on the home screen when the download finishes.

Only iPhones whose UDID is registered in the Apple Developer portal can install the builds.

### Add an iPhone

Register the iPhone's UDID in the Apple Developer portal (Certificates, Identifiers & Profiles → Devices),
then push any commit. Each build regenerates the Ad Hoc profile with every registered device. The build
summary shows how many devices the profile includes.

## CI/CD

`.github/workflows/build.yml` runs on every push to any branch except `gh-pages`, and manually through
*Run workflow* (with an option to force an unsigned build). It uses a `macos-15` runner with the newest
Xcode 26.

| Branch | Tag | GitHub release |
|---|---|---|
| `main` | `0.x.0`, where `x` is one more than the last `0.x.0` tag | Stable, marked *Latest* |
| any other | `build-<run_number>-<sha7>`, e.g. `build-30-1bca82e` | Pre-release |

The build name is also embedded in the app (Settings → Build).

Builds are never cancelled: runs on `main` are serialized in the `main` concurrency group and every other run
has its own group. GitHub keeps at most one pending run per group, so if several pushes to `main` queue up
while a build is running, only the newest pending one runs.

### Required secrets

Add these as **repository** secrets (Settings → Secrets and variables → Actions). This is a personal
repository, so they cannot come from an organization.

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | Key ID of an App Store Connect API key |
| `ASC_ISSUER_ID` | Issuer ID shown on the App Store Connect API keys page |
| `ASC_KEY_P8` | Full contents of the `.p8` file (a **Team Key** with the **Admin** role) |
| `APPLE_TEAM_ID` | Apple Developer Team ID |

- With all four secrets the build is signed (Ad Hoc), released and published to GitHub Pages.
- Without any of them the workflow builds an unsigned IPA and uploads it as a workflow artifact only.
- With only some of them the workflow fails with an error that names the missing ones.

### What the signed build does

1. `scripts/asc.py check` verifies the API key (ES256 JWT signed with `openssl`) and that at least one iOS
   device is registered.
2. It records the serial numbers of the "Apple Development" certificates already in the keychain.
3. `xcodebuild archive` with automatic signing (`-allowProvisioningUpdates` and the API key). Xcode registers
   the App ID and creates the profiles itself. The bundle ID `com.leonardoramirezr.voicenotesbyleoneralabs`
   is passed as the `APP_BUNDLE_IDENTIFIER` build setting (extensions would use `<bundle>.<suffix>`).
4. `xcodebuild -exportArchive` with `method=release-testing` and automatic signing, which uses the
   cloud-managed distribution certificate and an Ad Hoc profile with every registered device.
5. `scripts/verify_ipa.py` checks that every bundle carries an Ad Hoc `embedded.mobileprovision` and prints
   the number of devices.
6. `scripts/publish-pages.sh` publishes the build to GitHub Pages and the release is created with the install
   link.
7. Always, at the end: the development certificate that `xcodebuild` created during the run is revoked through
   the App Store Connect API. Certificates that existed before the run are never touched.

### GitHub Pages

The site lives in the `gh-pages` branch, with one folder per tag (`VoiceNotes.ipa`, `manifest.plist`,
`index.html` with the install button, `build.json` and icons). The root page lists every build and has a
button for the latest stable version. All `main` builds are kept, plus the newest 20 builds of other branches.
The branch is rewritten as a single commit on every publish so IPAs do not pile up in the history.

**After the first signed build**, enable Pages once: Settings → Pages → *Build and deployment* → Source
*Deploy from a branch* → Branch `gh-pages`, folder `/ (root)` → Save.

GitHub Pages sites have a 1 GB size limit; keeping every `main` build will eventually need old releases to be
removed from the branch by hand.

## Development

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open VoiceNotes.xcodeproj
```

To run on your own device, set your team in the target's Signing settings (or pass `DEVELOPMENT_TEAM`).

### Layout

| Path | Contents |
|---|---|
| `App/` | SwiftUI app: screens, recorder, speech, settings, localization |
| `Packages/VoiceNotesCore/` | Platform-independent logic: note text, checklists, diff, Groq client, prompts and JSON schemas, edit planning and application, Simplenote login client |
| `Packages/VoiceNotesSync/` | Core Data model, `Note` class and the Simperium sync engine |
| `scripts/` | CI helpers (`ci.py`, `asc.py`, `verify_ipa.py`, `pages_site.py`, `publish-pages.sh`, `check_strings.py`) and their tests |

### Tests

```sh
python3 -m unittest discover -s scripts/tests   # CI scripts
python3 scripts/check_strings.py                # English/Spanish strings
swift test --package-path Packages/VoiceNotesCore
swift test --package-path Packages/VoiceNotesSync   # macOS only (Simperium binary)
```

`VoiceNotesCore` builds on Linux too, so its tests run anywhere with a Swift 6 toolchain.

## Notes

This is an independent app. It talks to the Simplenote service the same way the official app does, but it is
not affiliated with Automattic or Simplenote. The official Simplenote iOS app (GPL-2.0) was studied to
reproduce its sync and login behavior; no code was copied from it. Simperium is MIT-licensed.
