# Session 17 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-020) →
3. `docs/sessions/progress-report-session16.md` → 4. `HANDOFF.md` («Релиз 0.11.0»).

## Состояние

- `main` — код **`ef7bc62`**, версия **0.11.0 (31)** поднята, не опубликована
  (опубликована 0.10.2). Пакеты **284/284**, `EscapementTests` **5/5**, Debug и
  Release без warnings (Xcode 27).
- UX-решения делегированы Claude (D-020) — не спрашивать владельца, решать по
  конвенциям Music.app и записывать.
- `audio-verify` после `fbe22e4` не подтверждён (TCC микрофона у терминала).

## Фокус сессии 17 — по порядку

1. **На MacBook:** выдать Terminal доступ к микрофону → `audio-verify` 24/24 →
   `RUBIS_RELEASE=1 ./Tools/make-dmg.sh` → GitHub release v0.11.0 + appcast
   (`HANDOFF.md`) → ретест обновления 0.10.2 → 0.11.0 (§9.11).
2. **Живая проверка S16** на стенде: Add to Playlist, shuffle/repeat после
   перезапуска, Cancel/Retry на серверном треке, ←/→ на полке, строка
   нечитаемой папки.
3. Остаток §9 и железо (ЦАП, VoiceOver, 8 часов) — вести владельца по шагам.

## Не забыть

- Mac Mini: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` для
  `swift test`/`xcodebuild`, `…/CommandLineTools` для `git`; сборка
  `CODE_SIGNING_ALLOWED=NO`; новые файлы App → `xcodegen generate`.
- Не гонять `swift test` параллельно с `xcodebuild`.
- Граф — `graphify update "$PWD"`.
- Радио не предлагать — владелец отклонил.
