# Progress report — Session 17 (2026-09-21, MacBook Pro M5 Max)

Код `ef7bc62` (не менялся), docs `089b102`. Пакеты в релизном прогоне —
`All package tests passed`, Release без warnings (Xcode 27.0, 27A266a).
**Rubis Music 0.11.0 (31) опубликована.**

## Сделано

- **`audio-verify` — 24/24 bit-perfect** на `ef7bc62`. Прошлое «0/24» было
  отсутствием TCC микрофона, не регрессом: на MacBook доступ выдан,
  `mic permission status: 3`, loopback `BlackHole 2ch`, все 24 фикстуры
  (44,1–192 кГц × 16/24 бита, синус и шум) сошлись побитово. Закрывает
  открытый пункт из `next_actions` и подтверждает тракт после `fbe22e4`.
- **Лицензия Xcode 27 на MacBook не была принята** — релизная сборка
  блокировалась на первом же шаге (`RELEASE BLOCKED: package tests failed`,
  под ним «You have not agreed to the Xcode license agreements»). `sudo`
  теряет `DEVELOPER_DIR` и берёт CLT, поэтому обычный
  `sudo xcodebuild -license accept` тоже падал. Рабочая форма записана в
  `HANDOFF.md`:
  `sudo DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -license accept`.
- **Релизный DMG собран строгим путём** (`RUBIS_RELEASE=1 ./Tools/make-dmg.sh`):
  тесты пакетов → Release-сборка → `audio-verify` внутри бандла → подпись
  Developer ID → нотаризация `status: Accepted` → staple → `spctl: accepted`.
  `sha256 de6a6a16e12b647902590e1b4b539e2c7aa3d7a4a79d3e31fd1219764fcfe0ae`,
  `length 12780332`, `edSignature 6jcS08LVsY/…SxhhAg==`.
- **Опубликована 0.11.0**: релиз
  https://github.com/Di-kairos/rubis-releases/releases/tag/v0.11.0 (заметки —
  черновик владельца из `HANDOFF.md`, без правок), appcast `0432d34` — новый
  `<item>` сверху, version 31.
- **Сверено по живому**, а не по локальным цифрам: скачанный по ссылке из
  appcast образ — 12 780 332 байта (совпадает с `length`), sha256 совпал,
  Gatekeeper на скачанной копии — `accepted / Notarized Developer ID`.
- **§9.11 ретест автообновления пройден**: установленная 0.10.2 (30) увидела
  фид, скачала и заготовила образ
  (`org.sparkle-project.Sparkle/Installation/…0.11.0.dmg`), на выходе тихо
  поставила 0.11.0 (31) — как и положено при `SUAutomaticallyUpdate = 1`
  (S14). Обновлённый бандл в `/Applications` — `accepted / Notarized
  Developer ID`, `TeamIdentifier=TA24A89R8H`, запускается.

## Решения в серых зонах

- Проверку обновления гнал не через меню «Check for Updates…», а сняв
  `SULastCheckTime` и перезапустив приложение: Sparkle уже проверял фид в
  07:28, до публикации, и по расписанию второй раз в эту сессию не пошёл бы.
  Путь установки при этом настоящий — плановая проверка, загрузка, тихая
  установка на выходе.
- Заметки релиза ушли дословно из черновика владельца (`HANDOFF.md`) —
  финальные тексты его зона (§9 глобальных правил), правок не вносил.

## Не сделано

- Живая проверка фич S16 (Add to Playlist, shuffle/repeat между запусками,
  Cancel/Retry на серверном треке, ←/→ на полке, строка нечитаемой папки) —
  руками и глазами, не начата.
- Остаток §9 чек-листа и железо: #04 DoP на ЦАПе, #26 VoiceOver, #32
  измерения, 8 часов без dropout, gapless.
- Кода в эту сессию не менялось — граф `graphify` не трогал (§15.2:
  чисто-документационная правка граф не двигает).
