# SourPipe

A port of [NewPipe](https://github.com/TeamNewPipe/NewPipe) to iOS: a native SwiftUI client for
YouTube, SoundCloud, PeerTube, Bandcamp and media.ccc.de, with no account, ads or tracking. It runs
the real [NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor), so fixes made upstream
reach this app by updating one pinned commit.

It is an independent project, not made or endorsed by the NewPipe team. It uses the name SourPipe so
that bug reports go here rather than to them.

## Build and run

You need a Mac with **Xcode 16 or later**. The extractor bundle is committed, so no Java is required.

1. Open `ios/SourPipe.xcodeproj`.
2. Select the **SourPipe** target, then **Signing & Capabilities**, and choose your **Team**. A free
   Apple ID works, though Apple makes free-account installs expire after 7 days. If Xcode says the
   bundle identifier is taken, change `app.sourpipe.SourPipe` to something of your own.
3. Pick a device or simulator and press **Run**. iOS 16 or later.

From the command line, without signing:

```sh
cd ios
xcodebuild -project SourPipe.xcodeproj -scheme SourPipe \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## What it does

- Browse, search with filters and suggestions, or paste a link (also `sourpipe://open?url=<link>`).
- Video pages with description, chapters, comments and replies, and related videos.
- Channels with their tabs, and playlists with Play all and Shuffle.
- Playback through AVPlayer: adaptive quality, a maximum quality setting, audio-only mode, background
  audio, lock-screen controls, Picture in Picture, AirPlay, a queue and resume.
- Stored on the device: subscriptions with a feed, history, local playlists and downloads (also
  visible in the Files app). Imports the `subscriptions.json` that NewPipe on Android exports.

### Not included

- Subtitles. The extractor returns them, but AVPlayer cannot add external tracks to these streams.
- Solving CAPTCHAs. When a service rate limits you, the app says so; try later or on another network.
- NewPipe's database import (only the subscriptions export is read), and sign-in of any kind.
- App Store distribution. Apple does not accept apps of this kind, so install it from Xcode.

## How it works

```
SwiftUI views ─ PlayerController (AVPlayer) ─ DownloadManager
        │ typed async calls (Extractor), JSON
ExtractorEngine.swift ── JSContext on its own thread; provides HTTP through URLSession, and timers
        │
extractor.jsbundle ───── NewPipeExtractor + jsoup + nanojson, compiled from Java by TeaVM
```

Java cannot run directly on iOS, and a JVM with a JIT is not allowed there. [TeaVM](https://teavm.org)
compiles the extractor's bytecode ahead of time to JavaScript, which iOS's built-in JavaScriptCore
runs. Blocking network calls in the Java code become TeaVM green-thread suspensions, so the extractor
is unmodified in structure and requests can overlap.

| Path | Purpose |
| --- | --- |
| `ios/SourPipe/Core` | Models, stream selection, library data. Foundation only; tested with `swift test`, including on Linux |
| `ios/SourPipe/{App,Extractor,Player,Views}` | The Apple-only app |
| `extractor/upstream.lock` | The NewPipeExtractor commit in use |
| `extractor/patches/` | Changes to upstream source, applied on top of that commit |
| `extractor/src/bridge` | The JSON API that Swift calls (`Main.java`, `Json.java`) |
| `extractor/src/overlay` | Replacements for libraries TeaVM cannot compile: Rhino helpers, protobuf-javalite, RE2/J |
| `extractor/src/shim` | The subset of `java.time` and `ReentrantLock` that TeaVM's class library lacks |
| `extractor/test/harness.mjs` | Live tests of the bundle in an empty JavaScriptCore global, as on iOS |
| `vendor/NewPipeExtractor` | Git-ignored working checkout, created by the scripts |

## Keeping the extractor current

Services change often, and when extraction breaks the fix normally lands upstream first.

```sh
scripts/update-extractor.sh            # newest commit on upstream's dev branch
scripts/update-extractor.sh v0.26.0    # or a specific tag or commit
```

This pins the commit in `extractor/upstream.lock`, re-applies `extractor/patches/`, rebuilds
`ios/SourPipe/Resources/extractor.jsbundle` and, if [Bun](https://bun.sh) is installed, runs the live
tests with the JIT off, as on iOS. Then commit the result and rebuild the app. It needs JDK 21
(`JAVA_HOME`, `PATH`, or unpacked in `.tools/`); Gradle comes with the wrapper.

If the patch no longer applies, the script stops with an error. Files it could merge have conflict
markers in `vendor/NewPipeExtractor`; files reported as `patch does not apply` need the change redoing
by hand, using the patch file as the guide. Then run `scripts/refresh-patch.sh` followed by
`scripts/build-extractor.sh`, without re-running the sync, which would discard your edits.

To carry a fix of your own, including one upstream has not merged:

```sh
scripts/sync-extractor.sh              # clean checkout with the current patches
# edit files in vendor/NewPipeExtractor
scripts/refresh-patch.sh               # saves every edit into the one patch file
scripts/build-extractor.sh
```

Things an update may need beyond that:

- **New Java APIs.** TeaVM names anything it cannot find, such as `Method java.util.Foo.bar() was not
  found`. Add a `T`-prefixed class to `extractor/src/shim`, or patch the call.
- **New `.proto` files or fields.** The two protobuf classes in `extractor/src/overlay` are written by
  hand from `extractor/src/main/proto` upstream, and must be changed to match.
- **Changed library versions.** The script prints upstream's jsoup and nanojson changes; copy them into
  `extractor/build.gradle.kts`.

`.github/workflows/update-extractor.yml` does this weekly and opens a pull request if the repository
is on GitHub.

## Tests

```sh
cd extractor && bun test/harness.mjs ../ios/SourPipe/Resources/extractor.jsbundle   # live services
cd ios && swift test                                                                # core logic

# Also decode live bridge output with the Swift models:
bun extractor/test/dump-fixtures.mjs /tmp/fixtures
cd ios && FIXTURE_DIR=/tmp/fixtures swift test
```

`BUN_JSC_useJIT=0` runs the harness without a JIT, which is how JavaScriptCore runs inside iOS apps.

## Known upstream behaviour

YouTube's `Trending` kiosk currently fails with `Could not get Trending name`. The other YouTube
sections work, and the default is `live`.

## Licence

GPL v3 or later, the same as NewPipe and NewPipeExtractor; see `LICENSE`. The bundle also contains
TeaVM's class library (Apache 2.0), jsoup (MIT) and nanojson (MIT), and `EcmaScriptTokenStream` in
upstream derives from Mozilla Rhino (MPL 2.0).
