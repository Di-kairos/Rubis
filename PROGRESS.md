---
project: Rubis
working_title: Rubis Music
ecosystem: standalone
repo: https://github.com/Di-kairos/Rubis.git
status: active
stack: [Swift 6, SwiftUI, SPM, SFBAudioEngine, CAAudioHardware, GRDB, SQLite/FTS5, Sparkle]
hosting: "local macOS app (arm64, macOS 15+), autoupdate через Di-kairos/rubis-releases"
head: "22c69fb"
tests: 70/70 (swift test, 5 packages)
last_session: 5
last_reviewed: 2026-08-07
keywords: [music-player, macos, bit-perfect, audio, flac, dsd, subsonic, navidrome, swiftui, sparkle]
next_actions:
  - "Прогнать docs/manual-checklist.md — то, что требует железа и ушей: внешний ЦАП, gapless на живом альбоме, 8 часов без dropout, VoiceOver, Reduce Motion / Increase Contrast глазами"
  - "Дизайн Jewel Box (D-007): владелец смотрит на своей библиотеке и возвращается с правками"
  - "Нажать «Check for Updates…» на установленной 0.2.x — живая проверка апдейта до 0.3.0 (фид и подпись проверены)"
  - "Развилка после фазы 7: фаза 6 Navidrome (D-003) или бэклог D-006 — решает Di-kairos"
  - "Прогнать замер скролла на 120-Гц панели (здесь дисплей 60 Гц): RUBIS_SCROLL_BENCH, см. TASKS фаза 5"
  - "Проверить на живом внешнем ЦАПе стартовый глоток после смены частоты (hog-путь)"
links:
  decisions: DECISIONS.md
  spec: SPEC.md
  design: DESIGN.md
  tasks: TASKS.md
  handoff: HANDOFF.md
  releases: https://github.com/Di-kairos/rubis-releases
  latest_report: docs/sessions/progress-report-session04.md
  latest_kickoff: docs/sessions/SESSION_05_KICKOFF.md
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
Фаза 7 (2026-08-07, та же сессия): опциональная иконка в меню-баре, mini player
поверх окон, глобальные медиа-клавиши за явным Accessibility, восстановление
позиции внутри трека и раздела сайдбара, Reduce Motion / Increase Contrast,
чистка декоративных иконок от VoiceOver, docs/manual-checklist.md на 40 пунктов.
Экран альбома починен по скриншоту владельца: название и артист больше не
схлопываются в узкой колонке, кнопки не теряют подписи (`ViewThatFits`,
`DSText(lines:)`, минимум 460 pt на detail-колонку).
Session 5 (2026-08-07): `phase/07-integration` слита в main (`94b0320`, тесты 70/70
перед merge), выпущен **Rubis Music 0.3.0** (build 3) в `rubis-releases` — DMG подписан
EdDSA, appcast обновлён, опубликованный файл сверен по SHA256.
Багрепорт владельца (78 папок-источников на живой библиотеке): сайдбар был VStack
без скролла → контент ~2200 pt распирал NavigationSplitView, layout окна разваливался
(тулбар/транспорт-бар выталкивало), AppKit падал исключением в NSViewUpdateConstraints
(SIGTRAP). Диагноз доказан DEBUG-харнессом на копии живой БД (78 vs 3 источника).
Фикс `9cacca9`: список сайдбара обёрнут в ScrollView. Выпущен **0.3.1** (build 4),
SHA256 опубликованного DMG сверен. Замечено: снапшот харнесса на macOS 26 не
захватывает NSScrollView-контент и vibrancy-сайдбар (белые области) — артефакт
снапшота, не бага рендера.
Владелец пересобрал библиотеку: одна родительская папка бокс-сета вместо 78
источников (бекап старой БД — `.claude/backups/library-2026-08-07-before-wipe.sqlite`).
Ещё три правки по живым жалобам: системное синее focus-кольцо вокруг списков на
macOS 26 погашено (`.focusEffectDisabled()`, свой индикатор — золото D-007),
слайдер громкости затонирован токеном accent, раздел **Now Playing** перестал быть
заглушкой — показывает очередь воспроизведения (◆ на играющем, двойной клик /
Return — прыжок на трек; `NowPlayingQueue.swift`, `queueSnapshot`/`playQueueItem`
в AppEnvironment). Выпущен **0.3.2** (build 5), SHA256 сверен.
HEAD: `22c69fb` — chore(release): bump version to 0.3.2 (build 5).

## Фазы (из TASKS.md)

- Фаза 0 — Каркас ✅
- Фаза 1 — Дизайн-система ✅ (галерея ⌘⇧D, WCAG-тест)
- Фаза 2 — БД и модель ✅ (100k FTS < 50 мс; v2_track_unavailable)
- Фаза 3 — Аудио-движок ✅ (**verify 24/24 bit-perfect**; hog только для внешних устройств)
- Фаза 4 — Локальная библиотека ✅ (обложки из папок, move-safe identity, unavailable)
- Фаза 5 — Интерфейс ✅ (acceptance весь зелёный: старт 208–219 мс, поиск < 50 мс,
  скролл 100k 59–60 fps, память 50k 221 МБ, клавиатура во всех разделах;
  слита в main, выпущена как 0.2.1)
- **Фаза 7 — Системная интеграция** ✅ по коду (меню-бар, always-on-top,
  глобальные медиа-клавиши, восстановление позиции и раздела, Reduce Motion /
  Increase Contrast, a11y-метки, чек-лист); слита в main, выпущена как **0.3.0**.
  Осталось: ручной прогон `docs/manual-checklist.md` на железе (acceptance)
- Фаза 6 — Subsonic/Navidrome (отложена, D-003) — развилка после фазы 7

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
