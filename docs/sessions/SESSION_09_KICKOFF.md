# Session 09 Kickoff — Rubis / Rubis Music

## Прочитать при старте
1. `PROGRESS.md` (frontmatter) → 2. `DECISIONS.md` (D-009 свежий) →
3. `docs/sessions/progress-report-session08.md` → 4. `HANDOFF.md`

## Состояние
- Ветка `main`, head `917f004`. Тесты **87/87**, Debug без warnings.
- Опубликовано: **0.8.7** (build 24) — appcast обновлён, SHA сверен.
- **0.8.8 (build 25) собрана и нотаризована, но НЕ опубликована.**
- Ветка `phase/06-subsonic` (запушена): packs 1–2 фазы 6, SubsonicKit 17 тестов.

## Первое дело — доиздать 0.8.8

DMG лежит на Рабочем столе владельца (`~/Desktop/RubisMusic-0.8.8.dmg`).
Если файла нет — пересобрать: `./Tools/make-dmg.sh` (подпись/нотаризация
пройдут заново, EdDSA и SHA256 напечатаются новые, тогда данные ниже
не годятся).

Команда владельцу (у Claude `gh release create` режет классификатор):

```
gh release create v0.8.8 ~/Desktop/RubisMusic-0.8.8.dmg \
  --repo Di-kairos/rubis-releases \
  --title "Rubis Music 0.8.8" \
  --notes "Play works again after the output device comes back. A file moved between source folders now moves instead of appearing twice."
```

После публикации: скачать ассет, сверить SHA256 с
`447125e0ae27970609fc2a3a701386cc2849f2c7ac685e8636a22a27e54de35f`,
затем добавить в `appcast.xml` первым item'ом и запушить:

```xml
<item>
  <title>0.8.8</title>
  <pubDate>Mon, 10 Aug 2026 22:05:00 +0300</pubDate>
  <sparkle:version>25</sparkle:version>
  <sparkle:shortVersionString>0.8.8</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
  <description><![CDATA[
    <ul>
      <li>Unplug your headphones and plug them back in: Play works again. Before, the player kept refusing to start until the track was launched by hand.</li>
      <li>Moving an album from one source folder to another now moves it. It used to arrive in the new folder while a dimmed, unplayable copy stayed behind in the old one.</li>
    </ul>
  ]]></description>
  <enclosure
    url="https://github.com/Di-kairos/rubis-releases/releases/download/v0.8.8/RubisMusic-0.8.8.dmg"
    sparkle:edSignature="oJS1Hsl5RnzcxGgc3KUHw7kj0jN0lYECGq+8SAF7im1wexCFDzRRL3oO27b9ubGiJnKoXFhgsvZOA4B0+FJwCw=="
    length="10571542"
    type="application/octet-stream"/>
</item>
```

Внимание: в main после 0.8.8 уже легли C и D (`39d3dc5`, `917f004`) — они
поедут следующим релизом, 0.8.8 их не содержит.

## Фокус S09 — продолжение списка фишек

Порядок владельца («делаешь всё это»), сделаны C, D; F оказалась готовой:

1. **E — приватная история прослушиваний.** Развилка на владельце:
   файл в Application Support (как `NetworkLedger`, без миграции) или
   таблица в БД (нормальные запросы «топ артистов за год», но схема после
   фазы 2 меняется только с его разрешения).
2. **B-local — DAC Dossier**: опрос подключённого ЦАПа (реальные частоты,
   отдаёт ли hog, потолок DoP/DSD) карточкой. Публичная база — НЕ делаем без
   отдельного слова: бэкенд и сбор данных против SPEC §1.2.
3. **A — Signal Path Receipt**: `Tools/audio-verify` внутрь UI, подписанный
   отчёт о тракте с экспортом. Самая крупная работа, отдельная фаза.
4. **Фаза 6** (`phase/06-subsonic`), packs 3–8: синхронизация каталога в те же
   таблицы, обложки с сервера в общий кэш, download-then-play с префетчем,
   LRU-кэш потоков, офлайн-поведение, тесты на фикстурах.

## Ждёт решения владельца
- Лицензия репозитория (файла нет, README это проговаривает).
- Тёмные скриншоты для README + лого на прозрачном фоне.
- Рамка продукта: список фишек написан языком запуска («маркетинг», «платно»,
  «форумы»), а SPEC §1.3 и README говорят «личный плеер, не продукт». Смена
  рамки меняет non-goals, лицензию и статус D-009.
- Публичная база ЦАПов (вторая половина B).
- Mac App Store (D-009) — по команде, начинать со спайка, не с кода.

## Не забыть
- `swift test` требует `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  — `xcode-select -p` на этой машине смотрит в CommandLineTools, иначе
  «no such module 'Testing'».
- Новые файлы App-таргета прописываются в `project.pbxproj` руками (явные
  ссылки, не синхронизированные группы) — иначе «cannot find X in scope».
- Версии: `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` в
  `Config/Escapement.xcconfig`.
- `security` (keychain) у Claude режется классификатором целиком — команды
  отдавать владельцу строкой.
- У владельца висит keychain-диалог на входе в Settings: записи ключей созданы
  старыми подписями. Лечение — удалить `claude-api-key` / `deepseek-api-key`
  (сервис `com.dikairos.escapement`) и ввести ключ заново.
