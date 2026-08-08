---
project: Rubis
working_title: Rubis Music
ecosystem: standalone
repo: https://github.com/Di-kairos/Rubis.git
status: active
stack: [Swift 6, SwiftUI, SPM, SFBAudioEngine, CAAudioHardware, GRDB, SQLite/FTS5, Sparkle]
hosting: "local macOS app (arm64, macOS 15+), autoupdate через Di-kairos/rubis-releases"
head: "d8cb4f2"
tests: 71/71 (swift test, 5 packages)
last_session: 5
last_reviewed: 2026-08-07
keywords: [music-player, macos, bit-perfect, audio, flac, dsd, subsonic, navidrome, swiftui, sparkle]
next_actions:
  - "Общий вердикт владельца по Jewel Box II (0.4.0 liner notes / 0.5.0 прибор / 0.6.0 витрина) → правки"
  - "Прогнать docs/manual-checklist.md — то, что требует железа и ушей: ЦАП, gapless, 8 часов без dropout, VoiceOver, обе a11y-настройки"
  - "Развилка после дизайн-итерации: фаза 6 Navidrome (D-003) или бэклог D-006 — решает Di-kairos"
  - "Прогнать замер скролла на 120-Гц панели (здесь дисплей 60 Гц): RUBIS_SCROLL_BENCH, см. TASKS фаза 5"
  - "Проверить на живом внешнем ЦАПе стартовый глоток после смены частоты (hog-путь)"
links_extra:
  design_proposal: https://claude.ai/code/artifact/a7800c64-1366-4892-978e-8fa89f15216a
links:
  decisions: DECISIONS.md
  spec: SPEC.md
  design: DESIGN.md
  tasks: TASKS.md
  handoff: HANDOFF.md
  releases: https://github.com/Di-kairos/rubis-releases
  latest_report: docs/sessions/progress-report-session05.md
  latest_kickoff: docs/sessions/SESSION_06_KICKOFF.md
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
Живой тест с ЦАПом (FiiO QX13, UAC2.0): плеер шёл только за системным
default-выходом — добавлен Picker «Output device» в Settings → Audio
(`preferredDeviceUID` уже был в AudioConfiguration; PlaybackEngine не тронут).
Заодно вылечен пробел: настройки Audio применялись только при открытии Settings —
теперь сохранённый конфиг толкается в плеер при старте
(`storedAudioConfiguration()` в AppEnvironment — единственный маппинг ключей).
По жалобам владельца: шапка у Now Playing (название + счётчик + общее время),
клик по источнику в сайдбаре ведёт в Albums. Выпущен **0.3.3** (build 6), SHA256
сверен. Открыто: жалоба «колонки и наушники играют разные альбомы» — у coreaudiod
спикерный контекст держали и Rubis (21768), и WebKit GPU (браузер); ждём
дискриминатор (пауза в Rubis глушит колонки или нет).
Развязка «колонки/наушники»: пауза в Rubis не глушила колонки → второй звук был
вкладкой браузера (WebKit держал audio-out). Чередование устройства по трекам —
флаппинг system default из-за hog (macOS уводит default с захваченного устройства);
лекарство — прибить выход в Rubis Settings → Audio (`preferredDeviceUID`), а
default оставить на колонках. По решению владельца Now Playing стал фокусным
экраном на всю площадь окна (две колонки: сайдбар + hero-обложка и очередь).
Выпущен **0.3.4** (build 7), SHA256 сверен.
Новая иконка приложения от владельца (рубин + волна на светлом фоне, тёмная в
Dock смотрелась мрачно) — все 10 размеров AppIcon.appiconset перегенерированы
sips из исходника 1254×1254. Выпущен **0.3.5** (build 8), SHA256 сверен.
HEAD: `57ba733` — chore(release): bump version to 0.3.5 (build 8).
Дизайн-вердикт владельца: «симпатично, но не оригинально» — начало итерации D-007.
Первые правки: Play на экране альбома — тонкое золотое кольцо вместо залитой
плашки, дубль-Shuffle удалён (есть в транспорте); в транспортной панели вместо
заглушки — обложка играющего альбома. Оба репо оформлены README с новым лого
(бейджи, карта пакетов, download-гайд в rubis-releases). Выпущен **0.3.6**
(build 9), SHA256 сверен.
HEAD: `c8352fb` — chore(release): bump version to 0.3.6 (build 9).
Дизайн-итерация «Jewel Box II» одобрена владельцем (артефакт-предложение:
диагноз Apple Music-подобия + три направления A/B/C, план тремя pack'ами).
**Pack 1 «Liner notes» выпущен как 0.4.0** (build 10): экран альбома как разворот
конверта — точечные лидеры (`DSDottedLeader` в DesignSystem, с Preview),
каталожная строка `numeric` между волосяными линейками, артист курсивным serif
(токен `displayArtist.italic`), секции Disc N для многодисковых, Now Playing тем
же языком. DESIGN.md §3/§5.4 обновлены. Впереди: Pack 2 «Прибор» (транспорт:
шкала с рисками, крупный тракт), Pack 3 «Витрина» (Albums, featured + полка).
HEAD: `2668aa2` — chore(release): bump version to 0.4.0 (build 10).
Session 05 продолжение (2026-08-08): **Pack 2 «Прибор» выпущен как 0.5.0** (build 11):
транспорт — шкала-линейка `DSRulerScale` (Canvas: риски шагом 8 pt, полотно, золотое
заполнение, игла) вместо слайдера; бейдж тракта — numeric капителью с разрядкой
(приборное чтение). Попутно вылечен LibrarySettings: список источников обёрнут
в ScrollView (та же болезнь, что была у сайдбара). DESIGN.md §5.1 обновлён.
Остался Pack 3 «Витрина» (Albums: featured + полка) — после вердикта владельца.
HEAD: `2d6b924` — chore(release): bump version to 0.5.0 (build 11).
По команде владельца («давай») **Pack 3 «Витрина» выпущен как 0.6.0** (build 12):
Albums — фокусный экран на всю площадь (двухколонный режим, как Now Playing):
featured-альбом 300 pt со «светом витрины» (`DS.Shadow.showcase*`, вторая
разрешённая тень §2.3) + его liner-notes трек-лист (AlbumDetail showcase-режим),
коллекция — горизонтальной полкой 108 pt на волосяной кромке (не-featured 0.78,
featured — золотое кольцо). Клик = featured, двойной = играть, ⌘L ставит
играющий. `AlbumsShowcase` заменил `AlbumsGrid` (AlbumCard остался для
Artists/Recently Added). DESIGN.md §2.3/§5.3 обновлены. Jewel Box II: все три
pack'а выпущены (0.4.0 / 0.5.0 / 0.6.0) — итерация ждёт общего вердикта владельца.
HEAD: `d4014b3` — chore(release): bump version to 0.6.0 (build 12).
Живой прогон витрины владельцем: трек-лист не отображался — дамп NSScrollView
(новый инструмент харнесса `RUBIS_DUMP_SCROLL=1`) показал высоту 0: полка без
явной высоты раздувалась до 320 pt и вместе с обложкой 300 pt отжимала весь
вертикальный бюджет. Фикс: полке фиксированная высота (108 + 2·lg), showcase-
обложка 240. Второй баг: пустой альбом-сирота после скана (0 треков) висел
анонимной плиткой — наблюдение albums теперь прячет альбомы без треков
(EXISTS-фильтр в Observation.swift, +тест; MusicLibrary 38/38, всего 71).
Выпущен **0.6.1** (build 13), SHA256 сверен. Тесты: 71/71.
HEAD: `2e836b2` — chore(release): bump version to 0.6.1 (build 13).
**D-008 (запрос владельца): аннотации альбомов.** Wikipedia (search/title →
page/summary, без ключа) как база, Claude API (`claude-opus-5`) как fallback;
opt-in в Settings → General → Album notes, ключ в Keychain (`KeychainStore`),
кеш навсегда в `Application Support/Escapement/album-info/`. UI: liner notes
читальным serif (новый токен `prose`) под трек-листом, источник подписан.
Выпущен **0.7.0** (build 14), SHA256 сверен. Владельцу: включить тумблер и
вставить ключ — Wikipedia работает и без ключа.
HEAD: `33198fb` — chore(release): bump version to 0.7.0 (build 14).
Вердикт владельца по месту заметок: на экране альбома внизу неуместно, в Now
Playing — самое то. Liner notes перенесены в hero-колонку Now Playing (свой
скролл, granica maxHeight — урок 0.6.1), с экрана альбома убраны; из
Claude-заметок вычищен markdown (звёздочки: промпт + strip при показе).
Выпущен **0.7.1** (build 15), SHA256 сверен.
HEAD: `4551912` — chore(release): bump version to 0.7.1 (build 15).
Ещё одна правка владельца: узкая колонка заметок читалась «пятном» — liner notes
теперь идут на всю ширину колонки очереди сразу под трек-листом и скроллятся
вместе с ним (как текст на обороте конверта). Выпущен **0.7.2** (build 16),
SHA256 сверен.
HEAD: `d8cb4f2` — chore(release): bump version to 0.7.2 (build 16).

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
