# HANDOFF — Rubis / Rubis Music

Актуальный указатель для «Продолжаем работу».

- Последняя сессия: **11** (2026-08-12: адаптивная вёрстка окна, MIT, audio-verify
  в бандле, подпись отчёта, лого на прозрачном фоне, CUE наполовину) — отчёт
  `docs/sessions/progress-report-session11.md`
- Следующая: **12** — kickoff `docs/sessions/SESSION_12_KICKOFF.md`
- Ветка `main`, head — см. `PROGRESS.md`. Тесты **181/181**, Debug без warnings
- **Живая ветка `phase/09-cue`** (`84cf8be`, 193/193): сканирование и
  воспроизведение рипов с CUE. Не влита — `audio-verify` не пройден (0/24,
  пустая запись у всех фикстур). Сначала доказательство, потом merge
- **Опубликована Rubis Music 0.9.0** (build 27); в `main` с тех пор накопилось
  невыпущенное — вёрстка, D-010 (MIT), D-011, D-012, лого
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

1. **Русский манифест переписан** — ждёт чтения. Понравится → английская
   версия (писать нативно, не переводить)
2. **Тёмные скриншоты README** — снять руками, рецепт в SESSION_12_KICKOFF:
   харнесс не рисует vibrancy-сайдбар, `screencapture` у Claude запрещён
3. **Личные детали в манифесте** — биографию Claude не выдумывает
4. **Mac App Store (D-009)** — по команде, два гейта
5. Публичная база ЦАПов (вторая половина B) — против SPEC §1.2

Закрыто в сессии 11: лицензия (MIT, D-010), `audio-verify` в поставке (D-011),
криптоподпись отчёта (D-012), лого на прозрачном фоне, CUE (наполовину).

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
