# Session 18 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-020) →
3. `docs/sessions/progress-report-session17.md` → 4. `HANDOFF.md`.

## Состояние

- `main` — код **`ef7bc62`**, docs `089b102`. **0.11.0 (31) опубликована**
  (2026-09-21): release v0.11.0 + appcast `0432d34`, sha256 `de6a6a16…`,
  Gatekeeper `accepted / Notarized Developer ID`. Невыпущенного в `main` нет.
- `audio-verify` — **24/24 bit-perfect** на `ef7bc62` (MacBook).
- **§9.11 закрыт**: 0.10.2 → 0.11.0 встала молча на выходе, бандл нотаризован.
- Пакеты 284/284, `EscapementTests` 5/5, Debug и Release без warnings
  (Xcode 27.0).
- UX-решения делегированы Claude (D-020) — не спрашивать владельца, решать по
  конвенциям Music.app и записывать.

## Фокус сессии 18 — по порядку

1. **Живая проверка фич S16** на 0.11.0 (стоит в `/Applications`): Add to
   Playlist (в том числе New Playlist), shuffle/repeat и порядок очереди
   после перезапуска, Cancel/Retry на серверном треке, ←/→ на полке альбомов,
   строка нечитаемой папки источника в сайдбаре. Вести владельца по шагам,
   расхождения — в баг-лист, а не в «наверное так и задумано».
2. **Остаток §9 чек-листа**: 9.8, 9.5, 9.1, 9.2, 9.12; с ЦАПом — 9.3/9.4/9.6.
3. **Железо и долгое**: #04 DoP (галка «This DAC decodes DoP»), #26 VoiceOver,
   #32 измерения, gapless, 8 часов без dropout — `docs/manual-checklist.md`.
4. Перепроверка аудитора по §8–§9 (F03 закрыт `33e5b75`, D-019) — если придёт.

## Не забыть

- MacBook: `sudo DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcodebuild -license accept` — лицензия принята 2026-09-21, повторять не надо.
- Mac Mini: `DEVELOPER_DIR=…/Xcode.app/…` для `swift test`/`xcodebuild`,
  CLT для `git`; сборка `CODE_SIGNING_ALLOWED=NO`; новые файлы App →
  `xcodegen generate`. Релиз — только с MacBook.
- Не гонять `swift test` параллельно с `xcodebuild`.
- Граф — `graphify update "$PWD"` после единицы работы с кодом.
- `gh release create` блокируется классификатором auto-mode — команду
  выполняет владелец строкой `! gh release create …`.
- Радио не предлагать — владелец отклонил.
