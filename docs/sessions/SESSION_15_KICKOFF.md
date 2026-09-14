# Session 15 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-014…D-018) →
3. `docs/sessions/progress-report-session14.md` (коротко) и
   `progress-report-session13.md` (суть аудита) → 4. `HANDOFF.md` →
5. `AUDIT_RESPONSE_2026-09-12.md` §4 и §8 (что открыто) и
   `AUDIT_PLAYER_2026-09-12.md` §14.4 (F03 — единственный незакрытый блокер аудитора).

## Состояние

- `main` — код `765bef9` (merge `phase/10-audit`), docs поверх. Пакеты
  **272/269/3** (3 skipped = 2 условных + F03 выключен), `EscapementTests`
  **2/2**, Debug и Release без warnings.
- Аудит 2026-09-12 отработан целиком, кроме **F03**. Релиза с этими правками
  ещё не было — последняя опубликованная **0.10.2 (30)**, она же теперь стоит
  на Mac Mini (сессия 14: тихое автообновление 0.10.0 → 0.10.2 подтверждено,
  чек-лист §6.3 закрыт).
- Ветка `phase/10-audit` не удалена (по команде).

## Фокус сессии 15 — по порядку

1. **F03 — решение владельца, потом код.** Рекомендация: миграция
   `track.content_hash` (FLAC — MD5 из STREAMINFO, 16 байт по фиксированному
   смещению; прочие — SHA-256 первых 64 КиБ + размер), заполняется на скане,
   переезд между источниками (шаг 4b) и уборка двойников (шаг 6) сливают
   только при совпадении, строки без отпечатка — не сливать. Включить
   `differentAudioMustNotReplaceAnOfflinePlaylistEntry`
   (`Packages/MusicLibrary/Tests/MusicLibraryTests/AuditFollowupTests.swift`).
   Схема БД — только с ведома владельца. Вопрос задан в S14, ответа нет.
2. **Живые проверки** — `docs/manual-checklist.md` §9 (12 пунктов) + прежние
   §1: ЦАП, DoP с галкой на UID и без, gapless против Play Next на слух,
   Space в полях Settings, Stop→Play→USB, битая БД → алерт.
3. **Релиз 0.11.0**: `RUBIS_RELEASE=1 ./Tools/make-dmg.sh` (строгий режим:
   тесты, Developer ID, нотаризация, `spctl`, `sign_update`), ретест
   обновления 0.10.2 → 0.11.0 (§9.11, Sparkle 2.9.6), заметки релиза — DSD
   через PCM до подтверждения ЦАПа (D-014), `text.muted`, Undo плейлистов,
   честный receipt Schema 2.
4. Остаток бэклога аудита (`AUDIT_RESPONSE_2026-09-12.md` §4) — по приоритету
   владельца.

## Не забыть

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` на Mac Mini
  (CLT активен) — иначе `swift test` не видит `Testing`, `xcodebuild` не идёт.
- Тесты приложения: `xcodebuild test -scheme Escapement -destination
  'platform=macOS' -only-testing:EscapementTests`.
- Новые файлы App/AppTests — `xcodegen generate`.
- Граф — `graphify update "$PWD"` (без LLM); `--update` здесь падает на ollama.
- Python-heredoc в Bash не переваривает `✓`/`✗` в исходнике — правки таких
  документов делать через Edit.
- `Tools/audit-regressions/` — байт-идентичные оригиналы файлов аудитора;
  в targets лежат те же тесты после `swift-format`.
- Sparkle у владельца в тихом режиме (`SUAutomaticallyUpdate = 1`): диалога
  нет, обновление ставится на Cmd+Q. «Не вижу обновления» — сначала
  `ls ~/Library/Caches/com.dikairos.escapement/org.sparkle-project.Sparkle/Installation`.
