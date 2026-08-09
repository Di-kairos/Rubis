<p align="center">
  <img src="docs/assets/logo.png" width="340" alt="Rubis Music logo">
</p>

<h1 align="center">Rubis Music</h1>

<p align="center">
  Personal hi-fi player for macOS. Bit-perfect or silent — never "close enough".
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-black" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-F05138" alt="Swift 6">
  <img src="https://img.shields.io/badge/arch-arm64-blue" alt="arm64">
  <img src="https://img.shields.io/badge/tests-72%2F72-brightgreen" alt="tests">
  <img src="https://img.shields.io/badge/bit--perfect-24%2F24-brightgreen" alt="bit-perfect 24/24">
  <img src="https://img.shields.io/badge/notarized-Apple-blue" alt="notarized">
</p>

<p align="center">
  <a href="https://github.com/Di-kairos/rubis-releases/releases/latest"><b>Download the latest build</b></a>
  ·
  <a href="SPEC.md">Spec</a>
  ·
  <a href="DESIGN.md">Design</a>
  ·
  <a href="DECISIONS.md">Decisions</a>
</p>

---

<p align="center">
  <img src="docs/assets/now-playing.png" alt="Now Playing: cover and queue side by side, liner notes below">
</p>

Rubis plays a local lossless library the way the file was mastered: the device
sample rate follows the track, the mixer is bypassed, the signal leaves the app
untouched. The audio path is not "probably fine" — `Tools/audio-verify` proves
bit-perfect output on 24 fixtures (44.1–192 kHz, 16/24-bit, FLAC/ALAC/WAV) before
any engine change lands.

## What it does

- **Bit-perfect playback** — exclusive device access (hog mode), automatic sample
  rate switching, no resampling, no software volume in the signal path. The badge
  in the transport bar tells the truth: rate, exclusivity, and any degradation.
- **Gapless** — track seams within an album are inaudible; the next decoder is
  armed ahead of time.
- **DSD** — DSF/DSDIFF via DoP when the DAC supports it, honest PCM conversion
  when it does not.
- **Output device pinning** — pick your DAC in Settings and stay on it, whatever
  the system default does.
- **Library at scale** — 100k-track library loads off the main thread, full-text
  search answers under 50 ms, the grid scrolls at 59–60 fps.
- **Sources** — folders on any volume; a disconnected disk greys tracks out
  instead of destroying history. Files are never deleted by a scan.
- **The usual comforts** — playlists, queue with shuffle/repeat, media keys,
  Now Playing as a full-window screen, mini player, optional menu bar presence,
  position restore across launches.
- **Self-updating** — Sparkle 2, EdDSA-signed feed in
  [rubis-releases](https://github.com/Di-kairos/rubis-releases).

- **Liner notes** — an optional note about the playing album, from Wikipedia and,
  where Wikipedia has nothing, from Claude or DeepSeek with your own API key.
  Off by default: the app makes no network call you did not ask for.

Design is its own thing: **Jewel Box** — warm near-black, serif display type,
a golden thread for selection, and a single garnet ◆ on the playing track.
No aggressive red anywhere.

<p align="center">
  <img src="docs/assets/albums.png" alt="Albums: featured record with its track list, the rest of the collection on a shelf">
</p>

<p align="center">
  <sub>Albums as a shop window: the featured record lit from the front, the
  collection on a shelf underneath, and a scroll indicator wearing the same
  ruby as the playing mark.</sub>
</p>

## Install

Grab the DMG from
[releases](https://github.com/Di-kairos/rubis-releases/releases/latest), drag
**Rubis Music** to Applications, launch it. The build is signed with a Developer
ID certificate and notarized by Apple, so it opens with a double click — no
right-click → Open, no Gatekeeper warning. Updates arrive in-app through Sparkle.

Requires macOS 15 or newer on Apple silicon.

## Architecture

Five SPM packages, dependencies point one way:

| Package | Role |
|---|---|
| `EscapementCore` | Shared models and contracts; depends on nothing |
| `PlaybackEngine` | Core Audio HAL, hog mode, rate switching, gapless queue |
| `MusicLibrary` | Scanner, metadata, GRDB/SQLite, FTS5 search, cover cache |
| `DesignSystem` | Every color, font, spacing, and radius token in the app |
| `SubsonicKit` | Empty shell until phase 6 (Navidrome/Subsonic) |

The app target is a thin SwiftUI shell; all logic lives in the packages.
Swift 6, strict concurrency complete, zero warnings.

## Build

```bash
./Tools/test.sh          # swift test for all five packages
./Tools/format.sh        # swift-format in-place (run before commit)
./Tools/audio-verify     # bit-perfect proof — required for engine changes
./Tools/make-dmg.sh      # Release build → signed, notarized, stapled DMG

# App target (requires full Xcode, not Command Line Tools):
xcodebuild -scheme Escapement -configuration Release
```

## Docs

| File | What's inside |
|---|---|
| `SPEC.md` | Technical spec: architecture, audio contract, DB schema, budgets |
| `DESIGN.md` | Design system: palette, typography, grid, components, motion |
| `TASKS.md` | Phases with acceptance criteria |
| `PROGRESS.md` / `DECISIONS.md` | Living state and decision log |
| `docs/manual-checklist.md` | Hardware acceptance: DAC, gapless, VoiceOver |

## Status

Phases 0–7 shipped: scaffold, design system, database, audio engine, local
library, full UI, system integration. Releases live in
[rubis-releases](https://github.com/Di-kairos/rubis-releases). Next fork in the
road: phase 6 (Navidrome/Subsonic).

Measured, not assumed: cold start 208–219 ms, search under 50 ms on 100k tracks,
scrolling 59–60 fps, 221 MB on a 50k-track library, and 24/24 bit-perfect
fixtures. Numbers that are not measured are not claimed.

## About this repository

A personal player built for one listener, published because the audio path,
the layout math and the release pipeline may be useful to read. It is not a
product: there is no support, no roadmap for feature requests, and no promise
of compatibility between versions. Issues and pull requests are welcome but
answered when time allows.

The audio contract is the part worth reading: `SPEC.md` §4 states what
bit-perfect means here, and `Tools/audio-verify` is the proof that has to pass
before any engine change is committed.
