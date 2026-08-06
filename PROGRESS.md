---
project: Rubis
working_title: Escapement
ecosystem: standalone
repo: https://github.com/Di-kairos/Rubis.git
status: active
stack: [Swift 6, SwiftUI, SPM, SFBAudioEngine, CAAudioHardware, GRDB, SQLite/FTS5]
hosting: "local macOS app (arm64, macOS 15+), не для App Store"
head: "9efb92f"
tests: 35/35 (swift test, 5 packages)
last_session: 1
last_reviewed: 2026-08-06
keywords: [music-player, macos, bit-perfect, audio, flac, dsd, subsonic, navidrome, swiftui]
next_actions:
  - "S02 фокус: фаза 5 pack 3 — плейлисты (UI поверх готового PlaylistRepository), mini-player (⌘⇧M), бюджеты §12 (старт <800мс, скролл 100k → List vs NSTableView)"
  - "Проверить на живом DAC стартовый глоток ~100мс после смены частоты (риск из фазы 3); лечение — preroll тишиной в PlaybackEngine"
  - "После acceptance фазы 5 — merge phase/05-interface, развилка: фаза 6 Navidrome (D-003) или фаза 7 системная интеграция — решает Di-kairos"
links:
  decisions: DECISIONS.md
  spec: SPEC.md
  design: DESIGN.md
  tasks: TASKS.md
  handoff: HANDOFF.md
  latest_report: docs/sessions/progress-report-session01.md
  latest_kickoff: docs/sessions/SESSION_02_KICKOFF.md
---

# PROGRESS — Rubis / Escapement

## Текущее состояние

Session 1 (2026-08-06): проект связан (git + X10 + память), принят пакет ТЗ Escapement —
bit-perfect macOS-плеер. SPEC/DESIGN/TASKS в корне. Кода нет, фаза 0 не начата.
HEAD: `9efb92f` — feat(ui): artists, tracks, recently added, cmd-F search (сессия 01 закрыта, фаза 5 packs 1–2).

## Фазы (из TASKS.md)

- Фаза 0 — Каркас ✅ (закрыта: сборка без warnings, тесты 8/8, окно запускается)


- Фаза 2 — БД и модель
- Фаза 3 — Аудио-движок (ключевая, bit-perfect верификация)
- Фаза 4 — Локальная библиотека
- Фаза 5 — Интерфейс
- Фаза 6 — Subsonic/Navidrome
- Фаза 7 — Системная интеграция и шлифовка

## Env Vars

Нет.
