---
project: Rubis
working_title: Rubis Music
ecosystem: standalone
repo: https://github.com/Di-kairos/Rubis.git
status: active
stack: [Swift 6, SwiftUI, SPM, SFBAudioEngine, CAAudioHardware, GRDB, SQLite/FTS5, Sparkle]
hosting: "local macOS app (arm64, macOS 15+), autoupdate через Di-kairos/rubis-releases"
head: "7ba870d"
tests: 50/50 (swift test, 5 packages)
last_session: 2
last_reviewed: 2026-08-06
keywords: [music-player, macos, bit-perfect, audio, flac, dsd, subsonic, navidrome, swiftui, sparkle]
next_actions:
  - "S03: вердикт владельца по дизайну Jewel Box (D-007) → шлифовка → релиз 0.2.1 в фид (проверка автообновления)"
  - "Открытые чекбоксы фазы 5: группировка поиска с клавиатурной навигацией, аудит скролла 100k"
  - "Глазами проверить раздел Tracks: выделение — золотая дымка, не системный синий (скриншот из сессии снять не удалось — нет прав Screen Recording)"
  - "Acceptance фазы 5 → merge phase/05-interface → развилка: фаза 6 Navidrome (D-003) или фаза 7 — решает Di-kairos"
  - "Проверить на живом внешнем ЦАПе стартовый глоток после смены частоты (hog-путь)"
links:
  decisions: DECISIONS.md
  spec: SPEC.md
  design: DESIGN.md
  tasks: TASKS.md
  handoff: HANDOFF.md
  releases: https://github.com/Di-kairos/rubis-releases
  latest_report: docs/sessions/progress-report-session02.md
  latest_kickoff: docs/sessions/SESSION_03_KICKOFF.md
---

# PROGRESS — Rubis / Rubis Music

## Текущее состояние

Session 2 (2026-08-06, MacBook Pro M5 Max): фаза 5 почти закрыта — плейлисты,
shuffle/repeat/очередь, медиа-клавиши + Now Playing, mini-player, автообновление
Sparkle (v0.2.0 опубликован в `rubis-releases`), продукт переименован в **Rubis Music**,
дизайн **Jewel Box** (D-007). Три бага вылечены с репро-доказательствами (hog-SIGABRT,
artwork-SIGTRAP, клик-играет-следующий). audio-verify **24/24 bit-perfect** на M5 Max,
старт 208–219 мс. Детали — `docs/sessions/progress-report-session02.md`.
HEAD: `7ba870d` — feat(ui): sortable track list with multi-selection
(колонки #/Title/Artist/Album/Duration/Format, ⌘/⇧-клик, `TrackSort` под тестами).

## Фазы (из TASKS.md)

- Фаза 0 — Каркас ✅
- Фаза 1 — Дизайн-система ✅ (галерея ⌘⇧D, WCAG-тест)
- Фаза 2 — БД и модель ✅ (100k FTS < 50 мс; v2_track_unavailable)
- Фаза 3 — Аудио-движок ✅ (**verify 24/24 bit-perfect**; hog только для внешних устройств)
- Фаза 4 — Локальная библиотека ✅ (обложки из папок, move-safe identity, unavailable)
- **Фаза 5 — Интерфейс** ← почти закрыта; осталось: группировка поиска,
  аудит скролла 100k → acceptance → merge
- Фаза 6 — Subsonic/Navidrome (отложена, D-003)
- Фаза 7 — Системная интеграция и шлифовка (часть сделана в S02: медиа-клавиши,
  mini-player, восстановление очереди)

## Дистрибуция

- DMG: `Tools/make-dmg.sh`; релизы + appcast: `Di-kairos/rubis-releases` (публичный).
- Sparkle EdDSA: приватный ключ `Rubis/.claude/sparkle/ed25519-private.pem` (X10, вне git).
- Ad-hoc подпись: первый запуск на чужой машине — right-click → Open.

## Env Vars

Нет (graphify на M5 Max: OLLAMA_* в ~/.zshrc — см. _global/MACHINE_SETUP.md).
