# HANDOFF — Rubis / Rubis Music

Актуальный указатель для «Продолжаем работу».

- Последняя сессия: **10** (2026-08-11: релиз 0.8.9, фаза 6 закрыта целиком
  packs 4–7, стенд Navidrome, манифест в репо, релиз 0.9.0) — отчёт
  `docs/sessions/progress-report-session10.md`
- Следующая: **11** — kickoff `docs/sessions/SESSION_11_KICKOFF.md`
- Ветка `main`, head — см. `PROGRESS.md`. Тесты **152/152**, Debug без warnings
- Ветка `phase/06-subsonic` влита в `main` (`a041baf`) и больше не нужна
- **Опубликована Rubis Music 0.9.0** (build 27), нотаризована, SHA256 сверён;
  невыпущенного в `main` нет
- **Репозиторий кода публичный**: https://github.com/Di-kairos/Rubis

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

1. **Лицензия репозитория** — файла нет (конкурент Bòcan open source с лицензией)
2. **Рамка продукта** — манифест написан продуктовым языком, SPEC §1.3 говорит
   «личный плеер, не продукт»; Bòcan бесплатен, open source и шире по фичам
3. **`audio-verify` в DMG** — сейчас только в репозитории; в поставке даёт то,
   чего нет ни у одного конкурента
4. **Криптоподпись отчёта о тракте** вместо SHA-256-отпечатка (нужен
   опубликованный публичный ключ, иначе смысла нет)
5. **CUE sheets** — единственный функциональный пробел из разбора конкурентов
6. **Манифест**: текст лежит в `MANIFESTO.md` (русский). Открыто — английский
   перевод и личные детали, если текст должен звучать биографично
7. Тёмные скриншоты для README + лого на прозрачном фоне
8. Публичная база ЦАПов (вторая половина B) — против SPEC §1.2
9. Mac App Store (D-009) — по команде, начинать со спайка

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
- Acceptance фазы 7 = прогон `docs/manual-checklist.md` на железе: внешний ЦАП,
  gapless, 8 часов без dropout, VoiceOver, обе a11y-настройки. Acceptance фазы 6
  закрыт весь, кроме bit-perfect с сервера на внешнем ЦАПе (§6a.5)
