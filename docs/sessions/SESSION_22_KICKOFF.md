# Session 22 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-022) →
3. `docs/sessions/progress-report-session21.md` → 4. `HANDOFF.md`.

## Состояние

- Код **`fa49a30`**, сверху только docs-коммиты. Опубликована **0.11.3 (34)**:
  sha256 `316e3cb9…`, appcast `be2558a` (item 34), Gatekeeper на скачанном
  образе `accepted / Notarized Developer ID`.
- Тесты 285/285 в пяти пакетах (прогнаны релизным путём на MacBook, Xcode 27.2),
  EscapementTests 13/13.
- Источник Subsonic `localhost` удалён из библиотеки — в базе остались только
  пять локальных папок.
- D-022: релизы собираются только на MacBook; секреты на Mac Mini не переносим.

## Фокус сессии 22 — по порядку

1. **Баг из S21**: строка «… is offline» переживает удаление источника.
   `sourcesDidChange()` не чистит `offlineServers`, статус висит до перезапуска
   (`App/AppEnvironment.swift:226`, `:679`). Шесть строк + тест в
   `EscapementTests`.
2. **Потерянные локальные файлы**: `BLUES` 60 `unavailable`, `Nu Jazz:Funk` 15.
   Сперва глазами владельца — переехали или удалены; потом решать, чинит ли это
   скан.
3. **Живьём на 0.11.3**: обложки после запуска, выделение в Tracks, имя New
   Playlist, мультивыделение в альбоме и плейлисте.
4. Железо: ЦАП (9.3/9.4/9.6), DoP, VoiceOver; SPEC §12 — 8 часов без dropout.

## Не забыть

- Debug-стенд на MacBook не сканирует (bookmarks привязаны к подписи) —
  живьём проверять установленную 0.11.3.
- Релиз только с MacBook (D-022). Версия, собранная на Mac Mini, ждёт
  следующей домашней сессии.
- Граф — `graphify update "$PWD"` после единицы работы с кодом.
- Радио не предлагать — владелец отклонил.
