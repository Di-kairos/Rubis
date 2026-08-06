# Rubis — Project Context for Claude Code

Универсальные правила (X10/GitHub sync, git workflow, session handoff, темп работы, тон, decision zones) — в **`/Volumes/X10 Pro/projects/CLAUDE.md`** (auto-loaded для всех проектов). Этот файл — только проектная специфика Rubis.

---

## Что это
Музыкальный плеер. Концепция и функционал — в проработке (Phase 0).

## Стек
TBD — фиксируется в первой рабочей сессии после выбора платформы (см. DECISIONS.md).

## Соглашения

### Код
- Комментарии и docstrings: **русский**
- Идентификаторы, имена файлов, ветки, commit subject: **английский**
- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`

### Секреты
Никогда не коммитим `.env*`. Список env-vars (без значений) — в `PROGRESS.md` → Env Vars.

## Нав-карта
- `PROGRESS.md` — текущее состояние, head, next_actions
- `DECISIONS.md` — лог ключевых решений
- `docs/sessions/` — kickoff/report файлы сессий
