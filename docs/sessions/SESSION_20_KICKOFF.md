# Session 20 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-021) →
3. `docs/sessions/progress-report-session19.md` → 4. `HANDOFF.md`.

## Состояние

- `main` — код **`be72cdf`** (версия **0.11.3 (34)**), не опубликована.
  В ней сверх 0.11.2 — только `44938dd` лицензии third-party в бандле.
- Опубликована 0.11.2 (33). Пакеты 285/285, EscapementTests 13/13.

## Фокус сессии 20 — по порядку

1. **На MacBook — релиз 0.11.3**:
   `RUBIS_RELEASE=1 ./Tools/make-dmg.sh ~/Desktop/rubis-0.11.3` → релиз
   v0.11.3 → сверка sha256 скачанного → appcast `<item>` 34 сверху → push.
   Заметка: «The app now carries the licence texts of the open-source
   components it uses.»
2. **На MacBook — перенос секретов релиза на Mac Mini** (порядок — отчёт
   S19, «Решения»): `.p12` Developer ID, `generate_keys -x`, затем на Mac
   Mini импорт + `notarytool store-credentials rubis`. Проверка:
   `security find-identity -v -p codesigning` видит Developer ID,
   `notarytool history --keychain-profile rubis` без ошибки.
3. **Живьём на 0.11.3**: обложки, выделение в Tracks, имя New Playlist,
   мультивыделение в альбоме и плейлисте.
4. Остаток S16, §9, железо.

## Не забыть

- Debug-стенд на MacBook не сканирует (bookmarks привязаны к подписи).
- `gh release create` может резаться классификатором — тогда строкой
  владельца `! gh release create …`.
- Граф — `graphify update "$PWD"` после единицы работы с кодом.
- Радио не предлагать — владелец отклонил.
