# Session 07 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` →
3. `docs/sessions/progress-report-session06.md` → 4. `docs/manual-checklist.md`

## Состояние
- Ветка `main`, head `607ff72`. Тесты **72/72**, Debug и Release без warnings.
- Выпущено: **0.8.6** (build 23). 0.8.5 и 0.8.6 подписаны
  `Developer ID Application: Daniel Diamant (TA24A89R8H)` и нотаризованы Apple;
  DMG открывается двойным кликом на чужой машине.
- **Репозиторий кода публичный**: https://github.com/Di-kairos/Rubis
- Релиз выпускается одной командой `./Tools/make-dmg.sh` — сборка, подпись,
  нотаризация, staple, EdDSA-подпись и SHA256. X10 для этого не нужен: ключи в
  связке машины, `sign_update` из SPM. Профиль нотаризации в связке — `rubis`.
- Библиотека владельца: два источника (AMBIENT, бокс-сет Blue Note), ЦАП FiiO QX13.

## Фокус S07 — решения владельца, потом код
1. **Лицензия репозитория** — MIT / AGPL / оставить «все права защищены».
   Сейчас файла нет, README это честно проговаривает.
2. **Тёмные скриншоты** для README (два, одинаковый размер окна, без пустой
   полосы внизу) и **лого на прозрачном фоне** без впечатанного текста.
3. **Развилка разработки**: фаза 6 Navidrome (D-003) или бэклог D-006
   (EQ/DSP, стриминги, скробблинг).
4. Ручной чек-лист фазы 7 на железе — то, что проверяется ушами.

## Не забыть
- Версии Sparkle: `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` в
  `Config/Escapement.xcconfig`; после публикации ассета сверять SHA256
  опубликованного DMG и только потом пушить appcast.
- `gh release create` у Claude блокируется классификатором — команду отдавать
  владельцу строкой.
- Keychain: у владельца диалог пароля до нажатия `Always Allow` (записи созданы
  старыми подписями). У новых пользователей его нет. Data-protection keychain
  проверен и недоступен вне App Store — не возвращаться к этой идее.
- Новый файл `docs/third-party.md` — LGPL-уведомление для `lame` и `libsndfile`,
  обновлять при смене набора зависимостей.
