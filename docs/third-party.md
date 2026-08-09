# Third-party software

Rubis Music ships the libraries below inside the app bundle. Each keeps its own
licence; this file is the notice that goes with the binary.

## Libraries

| Component | Licence | Role |
|---|---|---|
| [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) | MIT | Decoding and audio format handling |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | MIT | SQLite access for the library database |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | MIT | In-app updates |
| [CAAudioHardware](https://github.com/sbooth/CAAudioHardware) | MIT | Core Audio HAL device access |

## Codecs bundled through SFBAudioEngine

`FLAC`, `ogg`, `vorbis`, `opus`, `mpc`, `mpg123`, `tta-cpp` and `wavpack` are
distributed under BSD-style or LGPL terms by their respective projects.

Two are worth naming explicitly, because their terms attach to the distributed
DMG:

- **lame** — GNU Library General Public License, version 2
- **libsndfile** — GNU Lesser General Public License, version 2.1

Both ship as separate dynamic frameworks inside `Rubis Music.app/Contents/
Frameworks/` and are linked at runtime, never statically. The application code
that calls them is published in this repository, so a user who wants to replace
either framework with their own build can do so: drop the rebuilt framework in
place, re-sign the bundle, and the app loads it.

Full licence texts travel with each package in the Swift Package Manager
checkout (`SourcePackages/checkouts/<package>/LICENSE.txt` in the build
directory) and in each upstream repository.
