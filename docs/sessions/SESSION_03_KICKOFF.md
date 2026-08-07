# Session 03 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-001..D-007) →
3. `docs/sessions/progress-report-session02.md` → 4. `TASKS.md` (фаза 5, открытые чекбоксы)

## Состояние
- Ветка `phase/05-interface`, тесты 45/45 в 5 пакетах, audio-verify **24/24 bit-perfect**
  (BlackHole, M5 Max), Release 0 warnings, холодный старт 208–219 мс.
- Приложение **Rubis Music** установлено, автообновление живое:
  релиз v0.2.0 в `Di-kairos/rubis-releases` (appcast проверен end-to-end).
- Дизайн Jewel Box (D-007) собран, ждёт вердикта владельца.

## Фокус S03
1. Фидбек владельца по Jewel Box → шлифовка дизайна.
2. Выпуск 0.2.1 в фид (`Tools/make-dmg.sh` → sign_update → appcast + gh release) —
   проверка автообновления у владельца/друга.
3. Открытые чекбоксы фазы 5: сортировка/мультивыделение, группировка поиска
   с клавиатурной навигацией, аудит скролла 100k.
4. Acceptance фазы 5 → merge в main → развилка: фаза 6 Navidrome (D-003) или
   фаза 7 (глобальные шорткаты, меню-бар, manual checklist) — решает Di-kairos.

## Релизный конвейер (памятка)
`./Tools/make-dmg.sh` → `.claude/sparkle/sign_update <dmg> --ed-key-file
.claude/sparkle/ed25519-private.pem` → новый `<item>` в
`../rubis-releases/appcast.xml` (подпись+length) → commit+push → `gh release create
vX.Y.Z <dmg>` в rubis-releases. Версия — `Config/Escapement.xcconfig`
(MARKETING_VERSION + CURRENT_PROJECT_VERSION bump, Sparkle сравнивает build number).

## Риски/заметки
- Ad-hoc подпись: у друга первый запуск right-click → Open.
- Позиция в треке при восстановлении очереди не восстанавливается.
- Глоток после смены частоты — проверить на живом внешнем ЦАПе (hog-путь).
- D-006: EQ/DSP, стриминги, скробблинг в бэклоге — НЕ делать без явной команды.
