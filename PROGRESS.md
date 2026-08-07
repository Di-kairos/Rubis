---
project: Rubis
working_title: Rubis Music
ecosystem: standalone
repo: https://github.com/Di-kairos/Rubis.git
status: active
stack: [Swift 6, SwiftUI, SPM, SFBAudioEngine, CAAudioHardware, GRDB, SQLite/FTS5, Sparkle]
hosting: "local macOS app (arm64, macOS 15+), autoupdate через Di-kairos/rubis-releases"
head: "447a1a1"
tests: 57/57 (swift test, 5 packages)
last_session: 3
last_reviewed: 2026-08-07
keywords: [music-player, macos, bit-perfect, audio, flac, dsd, subsonic, navidrome, swiftui, sparkle]
next_actions:
  - "РАЗВИЛКА ЗА ВЛАДЕЛЬЦЕМ: фаза 6 Navidrome (D-003) или фаза 7 (глобальные шорткаты, меню-бар, manual checklist)"
  - "Вердикт владельца по дизайну Jewel Box (D-007) → шлифовка → релиз 0.2.1 в фид (проверка автообновления)"
  - "Прогнать замер скролла на 120-Гц панели (здесь дисплей 60 Гц): RUBIS_SCROLL_BENCH, см. TASKS фаза 5"
  - "Проверить на живом внешнем ЦАПе стартовый глоток после смены частоты (hog-путь)"
links:
  decisions: DECISIONS.md
  spec: SPEC.md
  design: DESIGN.md
  tasks: TASKS.md
  handoff: HANDOFF.md
  releases: https://github.com/Di-kairos/rubis-releases
  latest_report: docs/sessions/progress-report-session03.md
  latest_kickoff: docs/sessions/SESSION_04_KICKOFF.md
---

# PROGRESS — Rubis / Rubis Music

## Текущее состояние

Session 2 (2026-08-06, MacBook Pro M5 Max): фаза 5 почти закрыта — плейлисты,
shuffle/repeat/очередь, медиа-клавиши + Now Playing, mini-player, автообновление
Sparkle (v0.2.0 опубликован в `rubis-releases`), продукт переименован в **Rubis Music**,
дизайн **Jewel Box** (D-007). Три бага вылечены с репро-доказательствами (hog-SIGABRT,
artwork-SIGTRAP, клик-играет-следующий). audio-verify **24/24 bit-perfect** на M5 Max,
старт 208–219 мс. Детали — `docs/sessions/progress-report-session02.md`.
Session 3 (2026-08-07): **фаза 5 закрыта полностью** — список треков с сортировкой
и мультивыделением, поиск с группами Artists/Albums/Tracks и клавиатурной
навигацией, клавиатура во всех разделах. Загрузка и сортировка 100k уведены с
MainActor (1.56 с / ≤ 0.4 с). Починен перехват `Space` и стрелок меню у текстовых
полей. Скролл на 100k измерен in-process харнессом: 59–60 fps при 60 Гц, 0–1.1%
опозданий → **SwiftUI остаётся, NSTableView не нужен**. Снимки окна (light/dark)
подтвердили золотое выделение и поймали два дефекта колонок.
HEAD: `447a1a1` — merge: phase/05-interface в main (фазы 0–5).

## Фазы (из TASKS.md)

- Фаза 0 — Каркас ✅
- Фаза 1 — Дизайн-система ✅ (галерея ⌘⇧D, WCAG-тест)
- Фаза 2 — БД и модель ✅ (100k FTS < 50 мс; v2_track_unavailable)
- Фаза 3 — Аудио-движок ✅ (**verify 24/24 bit-perfect**; hog только для внешних устройств)
- Фаза 4 — Локальная библиотека ✅ (обложки из папок, move-safe identity, unavailable)
- Фаза 5 — Интерфейс ✅ (acceptance весь зелёный: старт 208–219 мс, поиск < 50 мс,
  скролл 100k 59–60 fps, память 50k 221 МБ, клавиатура во всех разделах)
- ← **Развилка: фаза 6 или фаза 7 — решает Di-kairos**
- Фаза 6 — Subsonic/Navidrome (отложена, D-003)
- Фаза 7 — Системная интеграция и шлифовка (часть сделана в S02: медиа-клавиши,
  mini-player, восстановление очереди)

## Дистрибуция

- DMG: `Tools/make-dmg.sh`; релизы + appcast: `Di-kairos/rubis-releases` (публичный).
- Sparkle EdDSA: приватный ключ `Rubis/.claude/sparkle/ed25519-private.pem` (X10, вне git).
- Ad-hoc подпись: первый запуск на чужой машине — right-click → Open.

## Env Vars

Только DEBUG, для замеров на синтетической библиотеке (см. TASKS фаза 5):
`RUBIS_DB_PATH` (путь к library.sqlite), `RUBIS_START_SECTION` (раздел при запуске),
`RUBIS_GENERATE_LARGE_LIBRARY` + `RUBIS_LARGE_LIBRARY_TRACKS` (генератор фикстуры в тестах).
В release-сборке ни одна не читается.

(graphify на M5 Max: OLLAMA_* в ~/.zshrc — см. _global/MACHINE_SETUP.md).
