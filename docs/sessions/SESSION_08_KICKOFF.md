# Session 08 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` →
3. `docs/sessions/progress-report-session07.md` → 4. `docs/manual-checklist.md`

## Состояние
- Ветка `main`, head `ea65c6a` (+ bump PROGRESS). Тесты **72/72**,
  Debug без warnings.
- Выпущено: **0.8.6** (build 23), подписано
  `Developer ID Application: Daniel Diamant (TA24A89R8H)` и нотаризовано.
- **В main лежит невыпущенное**: переключатель `Appearance`
  (Settings → General: System / Light / Dark). Уедет следующим релизом.
- **Релиз с этой машины невозможен**: `security find-identity -v -p codesigning`
  → 0 identities, Developer ID на второй машине. Там релиз одной командой
  `./Tools/make-dmg.sh` (сборка → подпись → нотаризация → staple → EdDSA + SHA256).
- Репозиторий кода публичный: https://github.com/Di-kairos/Rubis
- Библиотека владельца: два источника (AMBIENT, бокс-сет Blue Note), ЦАП FiiO QX13.

## Фокус S08 — решения владельца, потом код
1. **Лицензия репозитория** — MIT / AGPL / оставить «все права защищены».
   Файла нет, README это проговаривает.
2. **Тёмные скриншоты** для README (два, одинаковое окно): теперь снимаются
   без переключения всей системы — Appearance → Dark, ⌘⇧3. Плюс **лого на
   прозрачном фоне** без впечатанных «RUBIS» и «HI-FI MUSIC PLAYER».
3. **Развилка разработки**: фаза 6 Navidrome (D-003) или бэклог D-006
   (EQ/DSP, стриминги, скробблинг).
4. Ручной чек-лист фазы 7 на железе — то, что проверяется ушами.

## Не забыть
- Версии Sparkle: `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` в
  `Config/Escapement.xcconfig`; после публикации ассета сверять SHA256
  опубликованного DMG и только потом пушить appcast.
- `gh release create` у Claude блокируется классификатором — команду отдавать
  владельцу строкой.
- Проверка сборки без сертификата: `xcodebuild … CODE_SIGN_IDENTITY=""
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` — компиляция проходит,
  падает только фаза re-sign вложенных бинарей Sparkle. Это нормально.
- Снимок окна без прав Screen Recording: `RUBIS_SNAPSHOT_PATH` + `RUBIS_DB_PATH`
  (временная БД, живая библиотека не трогается) + `RUBIS_HARNESS_EXIT`.
  Белый сайдбар на снимке — артефакт vibrancy на macOS 26, не баг.
- Keychain: у владельца диалог пароля до `Always Allow` (записи созданы старыми
  подписями). У новых пользователей его нет. Data-protection keychain проверен
  и вне App Store недоступен — не возвращаться.
- `docs/third-party.md` — LGPL-уведомление для `lame` и `libsndfile`.
