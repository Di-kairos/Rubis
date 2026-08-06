# Progress Report — Session 01 (2026-08-06, рабочий Mac Mini)

## Сделано

- **Проект связан**: git + GitHub `Di-kairos/Rubis`, X10, память Claude (симлинк), graphify-граф.
- **Принят пакет ТЗ Escapement** (bit-perfect macOS-плеер): SPEC/DESIGN/TASKS/CLAUDE в корне.
- **Фаза 0 закрыта**: 5 SPM-пакетов, архитектурный тест зависимостей, xcodeproj через XcodeGen
  (`project.yml` — source of truth), swift-format, entitlements. Xcode 26.6 установлен на Mini.
- **Фаза 1 закрыта**: дизайн-система — Palette/Tokens (Obsidian+Porcelain), 8 примитивов,
  WCAG-тест контраста, галерея `⌘⇧D` (⌘⌥D занят системой). Визуально принята.
- **Фаза 2 закрыта**: GRDB 7.11.1, схема v1 по SPEC §5.1 (FTS5 + contentless_delete=1),
  репозитории, ValueObservation, нормализация имён. Перф: 100k треков, FTS < 50 мс.
- **Фаза 3 закрыта — ключевая**: SFBAudioEngine 0.9.1 + CAAudioHardware 0.7.1,
  `AudioDeviceController` (hog, частоты, mixing off raw-HAL, HAL-громкость, death watch),
  `Player` actor (очередь, gapless, честный isBitPerfect), DSD DoP/PCM, SampleRatePolicy+тесты.
  **`audio-verify`: 24/24 bit-perfect** (BlackHole loopback, 6 частот × 16/24 бит).
- **Фаза 4 закрыта**: LibraryScanner (bookmarks, инкрементальность mtime+size, TaskGroup,
  батчи 500), MetadataReader (§5.3), CoverCache (3 размера lazy), FolderWatcher (FSEvents 2s).
  Перф 10k: 5.2 с (бюджет 48 с).
- **Фаза 5 в работе** (packs 1–2 из ~3): главное окно 3 колонки + транспорт с бейджем и
  поповером тракта, сетка/детали альбомов (живое GRDB-наблюдение), drag&drop папки в окно,
  Artists/Tracks/Recently, поиск ⌘F (FTS live), Settings (Library/Audio), хоткеи Space/⌘←→/⌘R/⌘F.
  **Живая проверка пройдена**: скан реального альбома, воспроизведение, бейдж
  `16/44.1 · Exclusive · BenQ MA270U` — bit-perfect на живом DAC.

## В процессе / осталось (фаза 5 pack 3)

- Плейлисты: создание, drag&drop треков, переупорядочивание (`PlaylistRepository` готов).
- Mini-player (⌘⌥M из ТЗ → взять свободный шорткат, напр. ⌘⇧M), NSPanel non-activating.
- Пустые состояния/inline-ошибки по SPEC §9 (частично), Problem files в Settings.
- Замер бюджетов §12: старт < 800 мс, скролл 100k (решение SwiftUI List vs NSTableView), поиск уже < 50 мс.
- Acceptance фазы 5: полная клавиатурная навигация, ноль модалок вне разрешённых.

## Ключевые решения сессии

- D-001 ЦАП не выбран → универсальная реализация (DoP if available). D-002 библиотека на
  внутреннем SSD и внешних томах. D-003 Navidrome отложен (фаза 6 после 0–5).
- FTS5 + `contentless_delete=1` (без него триггеры не могут удалять). XcodeGen для xcodeproj.
- MusicLibrary получил зависимость SFBAudioEngine (AudioFile для метаданных — та же тройка §3.2).
- Типографика: display → Bold, артист под названием — акцентом (решение Di-kairos, DESIGN §3).
- **Риск зафиксирован в TASKS**: холодный аудио-граф после смены частоты глотает ~100 мс
  старта (в verify обойдено прогревом). Проверить на живом DAC; лечение — preroll тишиной.

## Машино-специфика (Mini установлено, дома поставить)

Xcode (App Store) + `xcodebuild -license accept`, `brew install xcodegen ffmpeg`,
`brew install blackhole-2ch` (для audio-verify; mic-permission через .app-обёртку /tmp/EscapementVerify.app —
пересоздаётся скриптом руками, см. Tools/audio-verify), fixtures: `./Tools/make-fixtures.sh`.
Память: `ln -sfn "/Volumes/X10 Pro/projects/Rubis/.claude/memory" ~/.claude/projects/-Volumes-X10-Pro-projects-Rubis/memory`.
