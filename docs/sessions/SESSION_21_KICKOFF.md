# Session 21 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-021) →
3. `docs/sessions/progress-report-session20.md` → 4. `HANDOFF.md`.

## Состояние

- `main` — код **`fa49a30`** (версия **0.11.3 (34)**), не опубликована.
  В ней сверх 0.11.2: `44938dd` лицензии в бандле, `e87a38f` свежий
  `audio-verify` в бандле (Xcode 27 сменил путь SwiftPM).
- `audio-verify` 24/24 на Mac Mini (`fa49a30`), бюджеты §12: CPU 0.99%,
  Play → сэмпл 61 мс.
- Опубликована 0.11.2 (33). Пакеты 285/285, EscapementTests 13/13.

## Фокус сессии 21 — по порядку

1. **На MacBook — релиз 0.11.3**:
   `RUBIS_RELEASE=1 ./Tools/make-dmg.sh ~/Desktop/rubis-0.11.3` → релиз
   v0.11.3 → сверка sha256 скачанного → appcast `<item>` 34 сверху → push.
   Перед сборкой — сверить, какой `audio-verify` лежит в бандле 0.11.2
   (mtime `Tools/audio-verify/.build/arm64-apple-macosx/release/audio-verify`
   на MacBook старше 2026-11-01 → в 0.11.2 уехал старый бинарь). Заметка: «The app now carries the licence texts of the open-source
   components it uses.»
2. **На MacBook — перенос секретов релиза на Mac Mini** (порядок — отчёт
   S19, «Решения»): `.p12` Developer ID, `generate_keys -x`, затем на Mac
   Mini импорт + `notarytool store-credentials rubis`. Проверка:
   `security find-identity -v -p codesigning` видит Developer ID,
   `notarytool history --keychain-profile rubis` без ошибки.
3. **Живьём на 0.11.3**: обложки, выделение в Tracks, имя New Playlist,
   мультивыделение в альбоме и плейлисте.
4. Остаток S16, §9, железо; §12 — 8 часов без dropout.

## Не забыть

- Debug-стенд на MacBook не сканирует (bookmarks привязаны к подписи).
- `gh release create` может резаться классификатором — тогда строкой
  владельца `! gh release create …`.
- Граф — `graphify update "$PWD"` после единицы работы с кодом.
- Радио не предлагать — владелец отклонил.
