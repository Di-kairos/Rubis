# Progress Report — Session 02 (2026-08-06, MacBook Pro M5 Max)

## Что сделано

**Фаза 5 pack 3 + strawberry-паки:**
- Плейлисты: создание (⌘⇧N), inline-переименование, d&d треков из всех списков,
  переупорядочивание (List.onMove), удаление; `append`/`rename`/`tracks(ids:)` в репозиториях.
- Strawberry-разбор (GPL → только adopt-pattern): #1 обложка из папки (PickBestArt:
  front→cover→folder→album, крупнейший файл); #2+#3 целостность библиотеки — перенос файла
  сохраняет id по сигнатуре size+mtime, пропавший файл → `unavailable` (миграция
  `v2_track_unavailable`), не удаление (D-004); #4+#5 shuffle/repeat (`PlaybackOrder`,
  чистая логика + тесты) и очередь playNext/enqueue.

**Продакшн-набор (обзор Swinsian/Audirvana/Colibri/foobar, в рамках SPEC):**
медиа-клавиши + Now Playing с обложкой; mini-player 240×80 (⌘⇧M); перемотка ←/→ ±5с;
⌘L reveal; восстановление очереди после перезапуска; аппаратная громкость в транспорте;
Tracks — вся библиотека виртуализированным List (снят лимит 5000).

**Три бага найдены и вылечены (репро-доказательства):**
1. `d55cab7` Play → SIGABRT: hog на встроенных динамиках валит SFB noexcept-обработчик
   (`IsFormatSampleRateAndChannelCountValid`). Hog теперь только для не-builtIn транспортов.
2. Artwork SIGTRAP: MainActor-замыкания MPMediaItemArtwork/MPRemoteCommand зовутся
   MediaRemote с чужой очереди → @Sendable-паттерн (двусторонний репро broken/fixed).
3. Клик по треку играл следующий: nowPlayingChanged от ручного старта принимался за
   gapless-переход → decoder identity tracking (двусторонний репро CLICK BUG/OK).

**Дистрибуция и идентичность:**
- Product name → **Rubis Music** (bundle id прежний); иконка из логотипа (asset catalog).
- Sparkle 2 autoupdate (D-005): публичный репо `Di-kairos/rubis-releases` (appcast + DMG),
  EdDSA-ключ на X10 `.claude/sparkle/ed25519-private.pem` (+ Keychain M5 Max),
  релиз v0.2.0 опубликован, фид проверен end-to-end. «Check for Updates…» в меню.
- `Tools/make-dmg.sh`; фикс сборки: re-sign вложенных фреймворков + отказ от library
  validation (ad-hoc без Team ID) — иначе dyld не грузит декодеры.
- Дизайн **Jewel Box** (D-007): serif-дисплей (New York), тёплый почти-чёрный, золотая
  дымка выделения, золотая нить в сайдбаре, кольцо на выбранном альбоме, токен `gem`
  (гранат) — только ◆-маркер играющего трека. WCAG-тесты прошли.

## Решения
D-004 unavailable-вместо-удаления; D-005 Sparkle (отмена запрета SPEC §13, 4-я зависимость);
D-006 EQ/DSP+стриминги+скробблинг из non-goals в бэклог (НЕ делать без команды);
D-007 визуальная идентичность. Бюджеты: старт 208–219 мс (лимит 800), FTS 100k <50 мс.

## Машинное (M5 Max)
BlackHole 2ch установлен (verify 24/24 на этой машине); xcodegen есть; `DEVELOPER_DIR`
нужен явно (xcode-select указывает на CLT); graphify: `OLLAMA_BASE_URL=…:11434/v1` +
`OLLAMA_MODEL=qwen3.6:latest` в ~/.zshrc (см. _global/MACHINE_SETUP.md).

## Осталось
- Владелец смотрит Jewel Box → правки по впечатлениям; затем DMG 0.2.1 в фид.
- Открытые чекбоксы фазы 5: сортировка/мультивыделение списков, группировка поиска
  с клавиатурной навигацией, аудит скролла 100k (fps не мерен).
- Позиция внутри трека при восстановлении очереди не восстанавливается (ponytail-ceiling).
- Глоток ~100 мс после смены частоты — проверить на живом внешнем ЦАПе.
- Acceptance фазы 5 → merge → развилка фаза 6/7 (решает Di-kairos).
