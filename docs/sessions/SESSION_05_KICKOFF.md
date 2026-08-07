# Session 05 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-001..D-007) →
3. `docs/sessions/progress-report-session04.md` → 4. `docs/manual-checklist.md`
   (что уже проверено, что нет) → 5. `TASKS.md` (фаза 7, фаза 6)

## Состояние
- Ветка `phase/07-integration` (запушена), main = фазы 0–5 (merge `447a1a1`).
- Тесты **70/70** в 5 пакетах, Debug и Release без warnings.
- Выпущено: **Rubis Music 0.2.1** в `rubis-releases` (DMG сверен по SHA256).
- Фаза 5 закрыта целиком, acceptance измерен. Фаза 7 закрыта **по коду**:
  меню-бар, mini player поверх окон, глобальные медиа-клавиши за явным
  Accessibility, восстановление позиции и раздела, Reduce Motion /
  Increase Contrast, a11y-метки, чек-лист на 41 пункт.

## Первое действие S05
**Merge не сделан.** Требует явного согласия владельца (§3.2 глобального
CLAUDE.md); в прошлой сессии команду блокировал классификатор до подтверждения.
```
git checkout main && git merge --no-ff phase/07-integration
git push origin main
```
После merge — `docs(progress): bump head` на merge-коммит (§2.3), затем релиз
**0.3.0** тем же конвейером, что 0.2.1 (памятка ниже).

## Фокус S05 — за владельцем
- Прогон `docs/manual-checklist.md` на железе — это и есть acceptance фазы 7:
  внешний ЦАП, gapless, 8 часов без dropout, VoiceOver, обе a11y-настройки.
- Вердикт по дизайну Jewel Box (D-007) → шлифовка.
- Развилка после фазы 7: **фаза 6 Navidrome** (D-003, SubsonicKit пустой, вкладка
  Server — заглушка) или бэклог D-006 (НЕ трогать без команды).

## Релизный конвейер (памятка)
Версия — `Config/Escapement.xcconfig` (MARKETING_VERSION + CURRENT_PROJECT_VERSION,
Sparkle сравнивает build number). Затем:
```
./Tools/make-dmg.sh /tmp
.claude/sparkle/sign_update /tmp/RubisMusic-X.Y.Z.dmg \
  --ed-key-file .claude/sparkle/ed25519-private.pem
# новый <item> первым в ../rubis-releases/appcast.xml (подпись + length)
cd ../rubis-releases && git commit && git push
gh release create vX.Y.Z /tmp/RubisMusic-X.Y.Z.dmg
```
Проверка: скачать опубликованный DMG и сверить SHA256 с подписанным.

## Инструменты проверки (только DEBUG, `App/DebugHarness.swift`)
Снимок окна изнутри процесса — прав Screen Recording не требует, им и проверять
вёрстку на живой библиотеке:
```
RUBIS_DB_PATH=<копия library.sqlite> RUBIS_START_SECTION=Albums \
  RUBIS_DEBUG_SELECT=1 RUBIS_SNAPSHOT_PATH=/tmp/shot.png \
  RUBIS_HARNESS_DELAY=7 RUBIS_HARNESS_EXIT=1 \
  "<DerivedData>/Build/Products/Debug/Rubis Music.app/Contents/MacOS/Rubis Music"
```
Ещё: `RUBIS_APPEARANCE=dark`, `RUBIS_SCROLL_BENCH=1` + `RUBIS_SCROLL_PTS_PER_SEC`,
генератор библиотеки — тест `generateLargeLibraryFixture` в MusicLibrary
(`RUBIS_GENERATE_LARGE_LIBRARY`, `RUBIS_LARGE_LIBRARY_TRACKS`).
Живую БД копировать, а не подключать оригинал.

## Риски/заметки
- `reentrant operation in its NSTableView delegate` в разделе Tracks (debug-лог).
  Источник — `List(selection:)`; подмена поддерева и `onKeyPress` проверены и ни
  при чём. Не ломает поведение, AppKit обещает assert.
- Индекс `(artist_id, album_id, disc_no, track_no)` под `tracks(byArtist:)` —
  правка схемы после фазы 2, спросить перед добавлением.
- Замер скролла делался на 60-Гц дисплее; на ProMotion прогнать заново.
- Метрика харнесса — ритм главного потока, не завершение отрисовки на GPU.
- Ad-hoc подпись: у друга первый запуск right-click → Open.
- Глоток ~100 мс после смены частоты — проверить на живом внешнем ЦАПе.
- D-006: EQ/DSP, стриминги, скробблинг в бэклоге — НЕ делать без явной команды.
