# Session 02 Kickoff — Rubis / Escapement (домашний MacBook Pro M5 Max)

## Прочитать при старте
1. `PROGRESS.md` (frontmatter: head, tests, next_actions)
2. `DECISIONS.md` (D-001..D-003)
3. `docs/sessions/progress-report-session01.md` — полный итог S01
4. `TASKS.md` — фазы 0–4 закрыты, фаза 5 в работе (packs 1–2 готовы)

## Состояние
- main = фазы 0–4 (audio-verify **24/24 bit-perfect**); ветка `phase/05-interface` = UI packs 1–2.
- Тесты 35+ зелёные во всех 5 пакетах. Живая проверка: играет bit-perfect на BenQ MA270U.

## Фокус S02 — фаза 5 pack 3
1. Плейлисты (создание/переупорядочивание/d&d) — репозиторий готов, нужен UI.
2. Mini-player (шорткат ⌘⇧M — ⌘⌥M занят системой, как и с галереей).
3. Бюджеты §12: холодный старт, скролл на 100k (сгенерить фикстуры, решить List vs NSTableView).
4. Acceptance фазы 5 → merge → фаза 6 (Navidrome) по решению Di-kairos.

## One-time bootstrap на домашней машине
- Xcode из App Store, лицензия; `brew install xcodegen ffmpeg blackhole-2ch`
- память Claude: `mkdir -p ~/.claude/projects/-Volumes-X10-Pro-projects-Rubis && ln -sfn "/Volumes/X10 Pro/projects/Rubis/.claude/memory" ~/.claude/projects/-Volumes-X10-Pro-projects-Rubis/memory`
- `git checkout phase/05-interface && git pull`; сборка: `xcodegen generate && xcodebuild -scheme Escapement build`
- фикстуры для тестов сканера: `./Tools/make-fixtures.sh`

## Риски/заметки
- Стартовый глоток ~100 мс после смены частоты (см. TASKS фаза 3 acceptance) — проверить на живом DAC дома.
- Настройки Audio задизейблены до реального ЦАП-решения (D-001).
