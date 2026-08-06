---
project: Rubis
working_title: Escapement
ecosystem: standalone
repo: https://github.com/Di-kairos/Rubis.git
status: active
stack: [Swift 6, SwiftUI, SPM, SFBAudioEngine, CAAudioHardware, GRDB, SQLite/FTS5]
hosting: "local macOS app (arm64, macOS 15+), не для App Store"
head: "f822f70"
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

Session 1 (2026-08-06, Mac Mini): фазы 0–4 закрыты и в main; **audio-verify 24/24
bit-perfect**; живой прогон подтверждён (бейдж `16/44.1 · Exclusive · BenQ MA270U`).
Фаза 5 packs 1–2 в ветке `phase/05-interface`. Детали — `docs/sessions/progress-report-session01.md`.
HEAD: `f822f70` — feat(ui): playlists — create, rename, drag & drop, reorder, delete.

## Фазы (из TASKS.md)

- Фаза 0 — Каркас ✅
- Фаза 1 — Дизайн-система ✅ (галерея ⌘⇧D, WCAG-тест)
- Фаза 2 — БД и модель ✅ (100k FTS < 50 мс)
- Фаза 3 — Аудио-движок ✅ (**verify 24/24 bit-perfect**; риск: старт после смены частоты)
- Фаза 4 — Локальная библиотека ✅ (10k скан 5.2 с)
- **Фаза 5 — Интерфейс** ← packs 1–2 готовы; pack 3: плейлисты, mini-player, бюджеты §12
- Фаза 6 — Subsonic/Navidrome (отложена, D-003)
- Фаза 7 — Системная интеграция и шлифовка

## Env Vars

Нет.
