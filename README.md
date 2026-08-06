# Rubis (working title: Escapement)

Personal bit-perfect audio player for macOS. Local lossless library + Subsonic/Navidrome.
Swift 6 / SwiftUI, native, single-user, not for App Store.

## Docs

- `SPEC.md` — technical spec: architecture, audio contract, DB schema, budgets
- `DESIGN.md` — design system: palette, typography, grid, components, motion
- `TASKS.md` — 8 phases with acceptance criteria
- `CLAUDE.md` — agent working rules
- `PROGRESS.md` / `DECISIONS.md` — living state and decision log

## Build

```bash
./Tools/test.sh          # swift test for all five packages
./Tools/format.sh        # swift-format in-place (run before commit)

# App target (requires full Xcode, not just Command Line Tools):
xcodebuild -scheme Escapement -configuration Release
```

## Status

Phase 0 — scaffold. See `PROGRESS.md`.
