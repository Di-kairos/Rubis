# Session 04 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-001..D-007) →
3. `docs/sessions/progress-report-session03.md` → 4. `TASKS.md` (фаза 5 закрыта,
   смотреть фазы 6 и 7)

## Состояние
- Ветка `phase/05-interface`, тесты **57/57** в 5 пакетах, Debug и Release без warnings,
  audio-verify 24/24 bit-perfect (замер S02), холодный старт 208–219 мс.
- **Фаза 5 закрыта, весь acceptance зелёный:** старт 208–219 мс (бюджет 800),
  поиск FTS и группы < 50 мс на 100k, скролл 100k 59–60 fps при 60 Гц с 0–1.1%
  опозданий, память 50k 221 МБ (бюджет 250), один разрешённый модальный алерт,
  клавиатурная навигация во всех разделах.
- Решение зафиксировано: **SwiftUI `List` остаётся**, NSTableView из SPEC §7.4 не нужен.

## Первое действие сессии 04
**Merge ветки — он не сделан.** Заблокирован классификатором разрешений в прошлой
сессии, требует явного согласия владельца (правило §3.2 глобального CLAUDE.md).
main — прямой предок, конфликтов нет:
```
git checkout main && git merge --no-ff phase/05-interface
git push origin main
```
После merge — `docs(progress): bump head` на merge-коммит (§2.3).

## Фокус S04 — за владельцем развилка
- **Фаза 6 — Subsonic/Navidrome** (D-003 отложил её; SubsonicKit пока пустой пакет,
  вкладка Server в настройках — заглушка), **или**
- **Фаза 7 — системная интеграция и шлифовка** (глобальные медиа-шорткаты через
  Accessibility, меню-бар, `docs/manual-checklist.md` — его до сих пор нет,
  хотя SPEC §11 его требует).

Параллельно: вердикт по дизайну Jewel Box (D-007) → шлифовка → DMG 0.2.1 в фид
(конвейер — в разделе ниже).

## Релизный конвейер (памятка)
`./Tools/make-dmg.sh` → `.claude/sparkle/sign_update <dmg> --ed-key-file
.claude/sparkle/ed25519-private.pem` → новый `<item>` в `../rubis-releases/appcast.xml`
(подпись+length) → commit+push → `gh release create vX.Y.Z <dmg>` в rubis-releases.
Версия — `Config/Escapement.xcconfig` (MARKETING_VERSION + CURRENT_PROJECT_VERSION,
Sparkle сравнивает build number).

## Инструменты замеров (появились в S03, только DEBUG)
`App/DebugHarness.swift` + `generateLargeLibraryFixture`:
```
cd Packages/MusicLibrary
RUBIS_GENERATE_LARGE_LIBRARY=/tmp/rubis-100k/library.sqlite \
  swift test --filter generateLargeLibraryFixture
RUBIS_DB_PATH=/tmp/rubis-100k/library.sqlite RUBIS_START_SECTION=Tracks \
  RUBIS_SCROLL_BENCH=1 RUBIS_SNAPSHOT_PATH=/tmp/shot.png \
  RUBIS_HARNESS_DELAY=10 RUBIS_HARNESS_EXIT=1 \
  "<DerivedData>/Build/Products/Debug/Rubis Music.app/Contents/MacOS/Rubis Music"
```
Снимок окна работает без прав Screen Recording — им и проверять вёрстку.
`RUBIS_APPEARANCE=dark` для тёмной темы, `RUBIS_SCROLL_PTS_PER_SEC` для скорости.

## Риски/заметки
- Замер скролла сделан на 60-Гц дисплее; на ProMotion прогнать заново.
- Метрика харнесса — ритм главного потока, не завершение отрисовки на GPU.
- Ad-hoc подпись: у друга первый запуск right-click → Open.
- Позиция в треке при восстановлении очереди не восстанавливается.
- Глоток после смены частоты — проверить на живом внешнем ЦАПе (hog-путь).
- Индекс `(artist_id, album_id, disc_no, track_no)` под `tracks(byArtist:)` напрашивается,
  но это правка схемы после фазы 2 — спросить перед добавлением.
- D-006: EQ/DSP, стриминги, скробблинг в бэклоге — НЕ делать без явной команды.
