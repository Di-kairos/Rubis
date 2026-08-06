---
project: Rubis
working_title: Escapement
ecosystem: standalone
repo: https://github.com/Di-kairos/Rubis.git
status: active
stack: [Swift 6, SwiftUI, SPM, SFBAudioEngine, CAAudioHardware, GRDB, SQLite/FTS5]
hosting: "local macOS app (arm64, macOS 15+), не для App Store"
head: "9875a87"
tests: 0/0
last_session: 1
last_reviewed: 2026-08-06
keywords: [music-player, macos, bit-perfect, audio, flac, dsd, subsonic, navidrome, swiftui]
links:
  decisions: DECISIONS.md
  spec: SPEC.md
  design: DESIGN.md
  tasks: TASKS.md
  spec_readme: docs/spec-readme.md
next_actions:
  - "Получить ответы Di-kairos на SPEC §15: модель ЦАП, где лежит библиотека, Navidrome в v1?"
  - "Фаза 0 (TASKS.md): Xcode-проект, 5 SPM-пакетов, xcconfig, swift-format, entitlements"
  - "Фазы строго по порядку; фаза 3 (аудио) — точка невозврата, только через Tools/audio-verify"
---

# PROGRESS — Rubis / Escapement

## Текущее состояние

Session 1 (2026-08-06): проект связан (git + X10 + память), принят пакет ТЗ Escapement —
bit-perfect macOS-плеер. SPEC/DESIGN/TASKS в корне. Кода нет, фаза 0 не начата.
HEAD — см. frontmatter.

## Фазы (из TASKS.md)

- **Фаза 0 — Каркас** ← сейчас
- Фаза 1 — Дизайн-система
- Фаза 2 — БД и модель
- Фаза 3 — Аудио-движок (ключевая, bit-perfect верификация)
- Фаза 4 — Локальная библиотека
- Фаза 5 — Интерфейс
- Фаза 6 — Subsonic/Navidrome
- Фаза 7 — Системная интеграция и шлифовка

## Env Vars

Нет.
