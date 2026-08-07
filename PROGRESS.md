---
project: Rubis
working_title: Rubis Music
ecosystem: standalone
repo: https://github.com/Di-kairos/Rubis.git
status: active
stack: [Swift 6, SwiftUI, SPM, SFBAudioEngine, CAAudioHardware, GRDB, SQLite/FTS5, Sparkle]
hosting: "local macOS app (arm64, macOS 15+), autoupdate через Di-kairos/rubis-releases"
head: "9d5fa1f"
tests: 57/57 (swift test, 5 packages)
last_session: 3
last_reviewed: 2026-08-06
keywords: [music-player, macos, bit-perfect, audio, flac, dsd, subsonic, navidrome, swiftui, sparkle]
next_actions:
  - "Вердикт владельца по дизайну Jewel Box (D-007) → шлифовка → релиз 0.2.1 в фид (проверка автообновления)"
  - "Ручной прогон Instruments: fps скролла на 100k-библиотеке → закрыть последний чекбокс фазы 5 и развилку SwiftUI/NSTableView"
  - "Глазами проверить: выделение в Tracks — золотая дымка, не системный синий; ↓ из поиска в результаты; пробел снова набирается в поиске"
  - "После этих проверок — merge phase/05-interface (нужно явное согласие) → развилка: фаза 6 Navidrome (D-003) или фаза 7"
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
Session 3 (2026-08-07): закрыты почти все чекбоксы фазы 5 — список треков с
сортировкой и мультивыделением, поиск с группами Artists/Albums/Tracks и
клавиатурной навигацией, клавиатура во всех разделах, загрузка и сортировка 100k
уведены с MainActor (1.56 с / ≤ 0.4 с, замер в тесте). Починен перехват `Space`
и стрелок меню у текстовых полей. Открыт один пункт: ручной замер fps скролла.
HEAD: `9d5fa1f` — feat(ui): keyboard navigation for grid, artists and playlists.

## Фазы (из TASKS.md)

- Фаза 0 — Каркас ✅
- Фаза 1 — Дизайн-система ✅ (галерея ⌘⇧D, WCAG-тест)
- Фаза 2 — БД и модель ✅ (100k FTS < 50 мс; v2_track_unavailable)
- Фаза 3 — Аудио-движок ✅ (**verify 24/24 bit-perfect**; hog только для внешних устройств)
- Фаза 4 — Локальная библиотека ✅ (обложки из папок, move-safe identity, unavailable)
- **Фаза 5 — Интерфейс** ← осталось одно: ручной замер fps скролла на 100k
  (Instruments) → acceptance → merge
- Фаза 6 — Subsonic/Navidrome (отложена, D-003)
- Фаза 7 — Системная интеграция и шлифовка (часть сделана в S02: медиа-клавиши,
  mini-player, восстановление очереди)

## Дистрибуция

- DMG: `Tools/make-dmg.sh`; релизы + appcast: `Di-kairos/rubis-releases` (публичный).
- Sparkle EdDSA: приватный ключ `Rubis/.claude/sparkle/ed25519-private.pem` (X10, вне git).
- Ad-hoc подпись: первый запуск на чужой машине — right-click → Open.

## Env Vars

Нет (graphify на M5 Max: OLLAMA_* в ~/.zshrc — см. _global/MACHINE_SETUP.md).
