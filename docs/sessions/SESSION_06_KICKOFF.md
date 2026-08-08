# Session 06 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` →
3. `docs/sessions/progress-report-session05.md` (там же машинные заметки Mac Mini)
→ 4. `docs/manual-checklist.md` → 5. дизайн-предложение:
https://claude.ai/code/artifact/a7800c64-1366-4892-978e-8fa89f15216a

## Состояние
- Ветка `main`, head `2668aa2` (+docs). Тесты **70/70**, Debug/Release без warnings.
- Выпущено: **0.4.0** (build 10) — Jewel Box II Pack 1 «Liner notes».
  Вся серия сессии 05: 0.3.0…0.3.6, 0.4.0 (см. progress-report-session05).
- Библиотека владельца: 1 источник (бокс-сет Blue Note), ЦАП FiiO QX13,
  выход прибит в Settings → Audio.

## Фокус S06
1. **Вердикт владельца по Pack 1** (liner notes на живой библиотеке) → правки.
2. **Pack 2 «Прибор»**: транспорт — шкала с рисками вместо системного слайдера
   (свой Path/Canvas, аккуратный хит-тест перемотки), тракт 24/192 крупно,
   тайминги табличные. PlaybackEngine НЕ трогается; если всё же тронется —
   `Tools/audio-verify` обязателен.
3. Затем Pack 3 «Витрина» (Albums: featured + полка, токен тени «свет витрины»,
   ревизия запрета теней DESIGN §2.3).

## Не забыть
- Ручной чек-лист фазы 7 — за владельцем (железо/уши).
- LibrarySettings: список источников без скролла (та же болезнь, что была
  в сайдбаре) — починить при первом заходе в Settings-код.
- Sparkle-версии: MARKETING_VERSION + CURRENT_PROJECT_VERSION (build!) в
  `Config/Escapement.xcconfig`; конвейер релиза — память в SESSION_05_KICKOFF.
- Mac Mini: DEVELOPER_DIR инлайном, OLLAMA_* инлайном, память не симлинкнута
  (см. progress-report-session05 §Машинное).
