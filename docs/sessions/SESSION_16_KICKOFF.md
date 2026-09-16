# Session 16 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-019) →
3. `docs/sessions/progress-report-session15.md` → 4. `HANDOFF.md` →
5. `docs/manual-checklist.md` §9 (что ещё ⏳) и `AUDIT_RESPONSE_2026-09-12.md` §9.

## Состояние

- `main` — код **`33e5b75`** (F03: `track.content_hash`, миграция v4), docs
  поверх (`c023773`+). Пакеты **277/277**, `EscapementTests` **2/2**, Debug без
  warnings на Xcode 27. Все пункты аудита §14 закрыты, ждём перепроверки.
- Релиза с правками аудита ещё нет — опубликована **0.10.2 (30)**. На Mac Mini
  нет Developer ID: релиз собирать на MacBook.
- §9 чек-листа: 9.7 ✅, 9.10 ✅, остальное ⏳/🔌.

## Фокус сессии 16 — по порядку

1. **Живые проверки §9** руками владельца (9.8, 9.5, 9.1, 9.2, 9.12; с ЦАПом
   9.3/9.4/9.6). Стенд на Mac Mini: `build/run-live-check.sh` (Debug на копии
   базы; источник «Collective Of Sound» добавлен в самом стенде — старые
   закладки Debug-сборка не читает). Статусы — в `docs/manual-checklist.md`.
2. **Релиз 0.11.0** (MacBook): `RUBIS_RELEASE=1 ./Tools/make-dmg.sh`, ретест
   обновления 0.10.2 → 0.11.0 (§9.11, Sparkle 2.9.6). Заметки релиза — см.
   progress-report-session15 «Осталось» п.2.
3. Бэклог по приоритету владельца: тихая ошибка резолва закладки при рескане;
   «Add to Playlist» в контекстном меню (UX — решение владельца);
   `AUDIT_RESPONSE` §4.

## Не забыть

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` для
  `swift test`/`xcodebuild`; для `git` на Mac Mini —
  `DEVELOPER_DIR=/Library/Developer/CommandLineTools` (лицензия Xcode 27).
- Сборка без сертификата: `xcodebuild … CODE_SIGNING_ALLOWED=NO`
  (пост-билд переподпись сама выходит). Тесты приложения:
  `xcodebuild test -scheme Escapement -destination 'platform=macOS'
  -only-testing:EscapementTests CODE_SIGNING_ALLOWED=NO`.
- Не гонять `swift test` пакетов параллельно с `xcodebuild` (гонка SPM-кэша).
- Копию базы стенда восстанавливать через `sqlite3 .backup`, WAL не трогать.
- Граф — `graphify update "$PWD"`; Codex — `codex exec -m gpt-5.5`.
