# Session 19 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-020) →
3. `docs/sessions/progress-report-session18.md` → 4. `HANDOFF.md`.

## Состояние

- `main` — код **`f4174ca`** (версия **0.11.1 (32)**), не опубликована.
  В ней: `26676b7` обложки из вычищенного кэша, `74bbfba` скан при запуске,
  `18a5cac` выделение мышью в Tracks.
- Пакеты 285/285 (MusicLibrary 104), Debug без warnings (Xcode 27).
- Нотаризация: `HTTP 403 — agreement missing or expired`. Профиль `rubis`
  в связке есть.

## Фокус сессии 19 — по порядку

1. **Релиз 0.11.1** — как только владелец примет соглашение Apple:
   `! xcrun notarytool history --keychain-profile rubis | head -5` без 403 →
   `RUBIS_RELEASE=1 ./Tools/make-dmg.sh ~/Desktop/rubis-0.11.1` → релиз
   v0.11.1 → сверка sha256 скачанного → appcast `<item>` 32 сверху → push.
   Заметки: «Album covers come back on their own if macOS clears the app's
   cache.» / «In Tracks, click, ⌘-click and ⇧-click select rows again;
   double-click plays.»
2. **Живьём на 0.11.1**: обложки после запуска, выделение в Tracks.
3. **Баг-лист**: имя New Playlist до создания; мультивыделение в альбоме и
   плейлисте (по Music.app, D-020).
4. Остаток живой проверки S16, §9, железо — как в kickoff 18.

## Не забыть

- Debug-стенд на MacBook не сканирует (bookmarks привязаны к подписи) —
  скан проверять подписанным билдом или тестами.
- `gh release create` может резаться классификатором — тогда строкой
  владельца `! gh release create …`.
- Граф — `graphify update "$PWD"` после единицы работы с кодом.
- Радио не предлагать — владелец отклонил.
