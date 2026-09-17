# HANDOFF — Rubis / Rubis Music

Актуальный указатель для «Продолжаем работу».

- Последняя сессия: **16** (2026-09-17, Mac Mini): код `ef7bc62` — версия
  **0.11.0 (31)** поднята, не опубликована (нет Developer ID/EdDSA/notary);
  UX-решения делегированы Claude (D-020): Add to Playlist, режимы между
  запусками, Cancel/Retry, стрелки на полке; пакеты 284, app 5/5. Отчёт
  `docs/sessions/progress-report-session16.md`
- Следующая: **17** — kickoff `docs/sessions/SESSION_17_KICKOFF.md`: на MacBook
  `audio-verify` (TCC микрофона) → релиз 0.11.0 → живая проверка S16

### Релиз 0.11.0 — шаги на MacBook

1. `git pull`, `RUBIS_RELEASE=1 ./Tools/make-dmg.sh` → `RELEASE OK`, из вывода
   взять `sparkle:edSignature`, `length`.
2. `gh release create v0.11.0 -R Di-kairos/rubis-releases ~/Desktop/RubisMusic-0.11.0.dmg`
3. `appcast.xml` — новый `<item>` сверху (version 31, shortVersion 0.11.0),
   push; сверить URL и SHA256 по живой ссылке; ретест 0.10.2 → 0.11.0 (§9.11).

Заметки (черновик, тон — владелец):
- A file that moved is recognised by its content, not by size and date alone:
  two different files can no longer swap identities. The first scan after the
  update reads a few small pieces of every file once.
- DSD goes out as PCM until you tick “This DAC decodes DoP” for your DAC in
  Settings → Audio.
- Playback transport, gapless and CUE seeking were hardened after an external
  audit; playlists survive deduplication, CUE rebuilds and server syncs.
- Secondary text is easier to read; playlist edits can be undone.
- A source folder that can no longer be read shows one line in the sidebar
  instead of failing silently.
- Add to Playlist in every track’s context menu, including a new playlist.
- Shuffle and repeat are remembered between launches, and the queue comes
  back in the same order.
- While a track downloads from your server, Play becomes Cancel; after a
  failure it becomes Retry.
- Arrow keys browse the album shelf when it has focus.

- Сессия **15** (2026-09-16, Mac Mini: **F03 закрыт** —
  `track.content_hash`, миграция v4, D-019, код `33e5b75`; Xcode 27 —
  `import Combine`, сборка без сертификата; живые проверки 9.7 и 9.10 ✅ на
  Debug-стенде `build/run-live-check.sh`) — отчёт
  `docs/sessions/progress-report-session15.md`
- Сессия **14** (2026-09-14, Mac Mini: без кода; живое
  автообновление Sparkle 0.10.0 → 0.10.2 подтверждено, тихий режим
  `SUAutomaticallyUpdate = 1` ставит на Cmd+Q без диалога) — отчёт
  `docs/sessions/progress-report-session14.md`
- Сессия **13** (2026-09-12…14: ответ на внешний аудит плеера — 33
  пункта, три раунда перепроверки; `phase/10-audit` **слита в main** `765bef9`
  по команде владельца) — отчёт `docs/sessions/progress-report-session13.md`,
  итог для аудитора `AUDIT_RESPONSE_2026-09-12.md` §1–§8
- `main` код `33e5b75` — все пункты аудита §14 закрыты (F03 — §9 ответа).
  Пакеты **277/277**, `EscapementTests` **2/2**, Debug без warnings (Xcode 27).
  Решения — D-014…D-019
- **Поведение изменилось для владельца:** DSD идёт через PCM, пока для его
  ЦАПа не стоит галка «This DAC decodes DoP» (Settings → Audio, D-014)
- Прежняя сессия **12** (2026-08-12: CUE влит и вылечен по битам, релиз
  0.10.0) — отчёт `docs/sessions/progress-report-session12.md`
- **CUE закрыт по коду и по битам**: ветка слита (`33ab227`), границы дорожек
  сверены с полным декодом (`CueDecodeTests`). Прошлое «0/24» у `audio-verify`
  было отсутствием TCC на захват, не регрессом — смотреть строку
  `mic permission status` (нужно 3). Осталось живое: тестовый рип уже лежит в
  `~/Music/CUE test - Shelly Manne 2-3-4/`, слушать границы
- **Опубликована Rubis Music 0.10.0** (build 28): CUE с точными границами, MIT,
  `audio-verify` в бандле, подписанный отчёт, адаптивная вёрстка, лого. SHA256
  скачанного файла сверён (`34198fa7…`), appcast запушен и проверен по живому
  URL. Невыпущенного в `main` не осталось
- **Репозиторий кода публичный**: https://github.com/Di-kairos/Rubis, лицензия MIT

## Стенд Navidrome (для работы над фазой 6)

- `brew install navidrome` — путь из документации (`/opt` + launchd + sudo)
  не нужен
- конфиг `~/.navidrome-test/navidrome.toml`: `MusicFolder` — папка с музыкой,
  `DataFolder` — `~/.navidrome-test/data`, `Port = 4533`
- запуск: `navidrome --configfile ~/.navidrome-test/navidrome.toml`
- админ создаётся в веб-морде `localhost:4533` (в S10 — `rubis` / `rubis-test`)
- в плеере: Settings → Server → адрес `http://localhost:4533` → Test connection
  → Save → Sync

## Релиз: где можно, где нельзя

- Релиз одной командой `./Tools/make-dmg.sh` — но **только на машине, где в
  связке лежит приватный ключ** `Developer ID Application: Daniel Diamant
  (TA24A89R8H)` и профиль нотаризации `rubis`. На машине сессии 10 (Mac Mini)
  оба на месте — релиз выпускается отсюда целиком. Где ключа нет, сборка идёт
  ad-hoc (`CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=""`)
- Проверка наличия ключа (команды владельцу — `security` у Claude режется):
  `security find-identity -v -p codesigning`,
  `xcrun notarytool history --keychain-profile rubis`
- **Перенос ключа на вторую машину**: Keychain Access → сертификат Developer ID
  Application → Export → `.p12` с паролем → на второй машине двойной клик.
  Профиль нотаризации завести заново:
  `xcrun notarytool store-credentials rubis --key <AuthKey_XXX.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>`
- Порядок публикации неизменен: ассет → сверка SHA256 скачанного файла → push
  appcast. `gh release create` режется предохранителем через раз — пробовать
  самому, доводить до конца без владельца

## Ждёт решения владельца

1. **Живая проверка CUE** — рип собран, ушей владельца ждёт (см. kickoff 13)
2. **Перемотка иглой** промахивается до блока FLAC (D-013, дополнение): чинить
   значит подменять seek у `AudioPlayer` — браться только по команде
3. **Личные детали в манифесте** — биографию Claude не выдумывает
4. **Mac App Store (D-009)** — по команде, два гейта
5. Публичная база ЦАПов (вторая половина B) — против SPEC §1.2

Закрыто в сессии 12: CUE целиком (D-013 + фикс границ), релиз 0.10.0, манифест
на двух языках наверху README, тёмные скриншоты, скролл 120 fps на 120 Гц.

## Знать до того, как копать

- **`swift test` без Xcode-тулчейна не идёт**: гонять с
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- **Новые файлы App-таргета**: не править `project.pbxproj` руками —
  `xcodegen generate` по `project.yml` (стоит через brew). Всё, что раньше
  дописывалось в Info.plist руками, должно быть в `project.yml`, иначе
  регенерация это стирает (в S10 так чуть не потерялся
  `SUScheduledCheckInterval`)
- **Снимки окна харнессом** (DEBUG): `RUBIS_WINDOW_SIZE=1000x640`,
  `RUBIS_FAKE_QUEUE=1`, `RUBIS_START_SECTION="Now Playing"`,
  `RUBIS_HARNESS_DELAY=10`, `RUBIS_HARNESS_EXIT=1`. Ad-hoc сборка не резолвит
  security-scoped bookmark подписанного релиза — без `RUBIS_FAKE_QUEUE` очередь
  пустая. Панели `List` и плавающий сайдбар в снимок не попадают — артефакт
  `cacheDisplay`, не баг
- **Тихое восстановление очереди оставляет `playbackState` в `idle`** — экраны
  подписываются на `env.queueRevision`, а не на id играющего трека (S09, баг
  «Queue is empty до первого Play»)
- **Журнал соединений и история прослушиваний — файлы**, не таблицы
  (`Application Support/Escapement/network-ledger.json`,
  `listening-history.json`): схема БД заморожена после фазы 2
- **Keychain**: у владельца диалог пароля всплывает, пока не нажат `Always
  Allow` (записи созданы старыми подписями). Data-protection keychain проверен
  опытом и недоступен вне App Store — к этой идее не возвращаться
- **SwiftUI-высоты**: два гибких скролла в одном стеке SwiftUI делит
  непредсказуемо — размеры задаются числом через GeometryReader. В S09 та же
  болезнь нашлась ещё в трёх местах (Now Playing, Albums, Tracks)
- **Wikipedia**: только `search/page` (полнотекстовый); `search/title` молчит
  на большинстве альбомов
- **Заметки**: Wikipedia первой, писатель (Claude/DeepSeek) — для того, чего в
  ней нет. Обратный порядок стоит десятков секунд на альбом
- **Subsonic**: старый сервер без `samplingRate` оставляет частоту нулём —
  не выдумывать 44100, на честности этого числа стоит SPEC §4
- **Треки с сервера** играют файлами: `StreamCache` качает целиком, имя файла —
  отпечаток `remote_id`, поэтому очередь собирается до приезда байтов. Склейку
  gapless приходится собирать повторно (`Player.rearmGapless`) — в момент старта
  трека следующий ещё качается
- **Молчащий сервер** метит свои треки флагом `unavailable` — тем же, что и
  пропавшие файлы. Отдельного оформления офлайна нет и не нужно
- **Sparkle** отдаёт «обновлений нет» ошибкой: в журнале соединений это успех,
  а не провал (вылечено в S10)
- **CUE-сегменты не начинаются сами**: `SFBFLACDecoder` после seek теряет блок
  с целевым сэмплом, поэтому `CueRegion.decoder(url:)` целится на блок раньше и
  доедает разницу (D-013, дополнение). Ломается модель — падает `CueDecodeTests`
- **CUE**: строка на дорожку в общем файле (`cue_start`/`cue_end`, схема v3).
  Сканер группирует известные строки по пути; файл, у которого число строк не
  сходится с листом, перечитывается даже при неизменных size/mtime — иначе
  подложенный позже лист не разрежет файл никогда. Сегменты не участвуют в
  распознавании переезда: подпись size+mtime у них общая
- **Новый файл в пакете не виден соседним пакетам**, пока у них не сброшен план
  сборки: `rm -f Packages/<pkg>/.build/build.db`. Симптом — «cannot find X in
  scope» при том, что файл на месте
- Acceptance фазы 7 = прогон `docs/manual-checklist.md` на железе: внешний ЦАП,
  gapless, 8 часов без dropout, VoiceOver, обе a11y-настройки. Acceptance фазы 6
  закрыт весь, кроме bit-perfect с сервера на внешнем ЦАПе (§6a.5)
