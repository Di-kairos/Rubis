# Escapement — техническое задание

> **Escapement** (спусковой механизм) — персональный аудиоплеер для macOS.
> Однопользовательский продукт. Не opensource, не для App Store, не для чужих машин.
> Рабочее название и bundle ID меняются в одном месте — см. §14.

---

## 1. Продукт

### 1.1 Что это

Нативный macOS-плеер для локальной lossless-библиотеки и собственного Subsonic/Navidrome-сервера,
с bit-perfect выводом звука и интерфейсом, спроектированным под одного человека.

Три принципа, в порядке приоритета при любом конфликте требований:

1. **Звук неприкосновенен.** Ни один пиксель UI не имеет права стоить сэмпла. Никакого ресемплинга,
   микширования или DSP на пути сигнала, если пользователь явно не включил обратное.
2. **Интерфейс молчит, пока к нему не обращаются.** Плеер — инструмент, а не витрина.
   Нет рекомендаций, нет соцфункций, нет уведомлений, нет онбординга.
3. **Отзывчивость важнее полноты.** Библиотека в 100k треков должна листаться так же,
   как библиотека в 100.

### 1.2 Целевой пользователь

Один. Владелец машины. Отсюда следуют важные упрощения, которыми **нужно** пользоваться:

- Нет мультиаккаунтности, нет ролей, нет sandbox-ограничений App Store.
- Нет миграций для чужих данных — схема БД может ломаться, если есть скрипт миграции.
- Нет локализации: интерфейс на английском, комментарии в коде на английском.
- Нет телеметрии, аналитики, crash-репортинга во внешние сервисы. Совсем.
- Нет сетевых запросов, кроме как к явно настроенному Subsonic-серверу и (опционально)
  к MusicBrainz/Cover Art Archive для обложек.

### 1.3 Non-goals для v1

Явно **не** делаем — не предлагать, не «закладывать на будущее», не писать заглушки:

- Редактирование тегов (чтение — да, запись — нет).
- Визуализация спектра, обложки на весь экран, «now playing» полноэкранные режимы.
- Синхронизация с iOS, iPhone-компаньон.
- Плагины, скриптинг, темы оформления.
- CD-риппинг, конвертация форматов, транскодирование.

> D-006 (2026-08-06): стриминговые сервисы, EQ/DSP и Last.fm-скробблинг сняты с
> non-goals решением владельца и живут в бэклоге TASKS «Что дальше». Не делать
> без отдельной команды.

---

## 2. Платформа и инструменты

| Параметр | Значение |
|---|---|
| Минимальная ОС | macOS 15.0 (Sequoia) |
| Разработка на | macOS 26 (Tahoe) |
| Язык | Swift 6.x, strict concurrency = complete |
| UI | SwiftUI, AppKit только там, где SwiftUI не тянет (§7.4) |
| Сборка | Swift Package Manager, монорепозиторий |
| Архитектуры | arm64 (Apple Silicon). x86_64 не поддерживаем. |
| Подпись | Local development signing / ad-hoc. Нотаризация не нужна. |
| Минимум зависимостей | Каждая новая внешняя зависимость требует явного обоснования в PR |

---

## 3. Архитектура

### 3.1 Структура репозитория

```
Escapement/
├── Escapement.xcodeproj/          # тонкая app-обёртка, вся логика в пакетах
├── App/                           # target: Escapement (SwiftUI @main)
│   ├── EscapementApp.swift
│   ├── Scenes/                    # окна, команды меню
│   └── Resources/
├── Packages/
│   ├── EscapementCore/            # домен: модели, протоколы, никаких зависимостей
│   ├── PlaybackEngine/            # аудио: вывод, устройства, очередь
│   ├── MusicLibrary/              # БД, сканер, метаданные, обложки
│   ├── SubsonicKit/               # клиент OpenSubsonic
│   └── DesignSystem/              # токены, примитивы, компоненты
├── Tools/
│   └── audio-verify/              # CLI для проверки bit-perfect (§4.6)
└── docs/
```

**Правило зависимостей** (нарушение = ошибка сборки, проверяется тестом на импорты):

```
App  →  DesignSystem, MusicLibrary, PlaybackEngine, SubsonicKit, EscapementCore
MusicLibrary  →  EscapementCore
PlaybackEngine  →  EscapementCore
SubsonicKit  →  EscapementCore
DesignSystem  →  (ничего)
EscapementCore  →  (ничего)
```

`EscapementCore` не импортирует SwiftUI. `DesignSystem` не импортирует ничего проектного.
Пакеты не знают друг о друге — связывает их только App через композицию.

### 3.2 Внешние зависимости

Ровно три. Больше — только через явное согласование.

| Пакет | Зачем | Лицензия |
|---|---|---|
| [`sbooth/SFBAudioEngine`](https://github.com/sbooth/SFBAudioEngine) | Декодирование (FLAC, ALAC, DSF/DFF, WavPack, Opus, Vorbis, MP3, AIFF, WAV), gapless-очередь, чтение метаданных через `AudioFile` | MIT (часть транзитивных зависимостей LGPL → линковать динамически) |
| [`sbooth/CAAudioHardware`](https://github.com/sbooth/CAAudioHardware) | Swift-обёртка над Core Audio HAL: перечисление устройств, hog mode, смена nominal sample rate, наблюдение за изменениями | MIT |
| [`groue/GRDB.swift`](https://github.com/groue/GRDB.swift) | SQLite: библиотека, FTS5-поиск, наблюдение за изменениями через `ValueObservation` | MIT |

> **Проверить перед стартом:** актуальные версии, требования к минимальной ОС и наличие
> нужных API (hog mode, nominal sample rate) в CAAudioHardware. Если API отсутствует —
> писать тонкую обёртку над `AudioObjectSetPropertyData` самостоятельно, это ~200 строк.
> Не подменять bit-perfect требование удобством библиотеки.

---

## 4. Аудио — главный контракт

Это раздел, ради которого пишется приложение. Всё остальное вторично.

### 4.1 Требование bit-perfect

Сигнал от файла до устройства проходит **без изменения битов**:

- Никакого ресемплинга. Частота дискретизации устройства выставляется под трек, а не наоборот.
- Никакого микширования с системными звуками — устройство переводится в exclusive-режим.
- Никакой регулировки громкости в цифровом домене приложением (§4.4).
- Никакой конвертации разрядности вниз, если устройство поддерживает исходную.

### 4.2 Вывод

Реализация — `PlaybackEngine`, публичный фасад `Player` (actor).

Требования к выводному тракту:

1. **Hog mode.** При старте воспроизведения захватывать устройство (`kAudioDevicePropertyHogMode`),
   при остановке — освобождать. Настраиваемо: `Settings.exclusiveAccess` (по умолчанию `true`).
   Если захват не удался — не молчать: показать статус в UI (§7.3, «badge деградации»),
   продолжить в shared-режиме.
2. **Отключение микшера.** `kAudioDevicePropertySupportsMixing = false`, где устройство это допускает.
3. **Смена частоты дискретизации.** Перед стартом трека читать `kAudioDevicePropertyAvailableNominalSampleRates`,
   выставлять точное совпадение. Если точного нет — выбрать кратное того же семейства
   (44.1 → 88.2 → 176.4 → 352.8; 48 → 96 → 192 → 384) и **явно пометить в UI как ресемплинг**.
   Кросс-семейный ресемплинг (44.1 → 48) — только с подтверждением пользователя в настройках.
4. **Пауза на переключении.** При смене частоты между треками возможен щелчок железа.
   Вставлять настраиваемую паузу (`Settings.sampleRateChangeDelay`, по умолчанию 300 мс),
   применять её **только** когда частота реально меняется.
5. **Gapless.** Внутри альбома с одинаковой частотой переходы бесшовные —
   очередь предзагружает следующий декодер. Использовать `AudioPlayer` из SFBAudioEngine,
   не изобретать свой ring buffer.
6. **DSD.** DSF и DSDIFF. Если устройство поддерживает DoP — отдавать DoP-пакеты как есть.
   Иначе конвертировать DSD→PCM 24/176.4 и пометить в UI. Настройка `Settings.dsdMode`:
   `.dopIfAvailable` (по умолчанию) / `.alwaysConvertToPCM`.

### 4.3 Форматы

Обязательно: FLAC, ALAC (.m4a), WAV, AIFF, DSF, DFF, Opus, Vorbis, MP3, AAC, WavPack, Monkey's Audio.
Всё это покрывается SFBAudioEngine — не писать собственные декодеры.

Частоты: 44.1–384 кГц. Разрядность: 16/24/32 bit integer и float.

### 4.4 Громкость

В bit-perfect режиме приложение **не трогает** цифровую громкость. Слайдер громкости в UI
управляет громкостью **устройства** через HAL (`kAudioDevicePropertyVolumeScalar`), если устройство
это поддерживает аппаратно. Если не поддерживает — слайдер скрыт, вместо него подсказка
«volume controlled by DAC». Никакого софтверного умножения сэмплов.

Исключение: если `Settings.exclusiveAccess == false`, разрешён обычный software volume —
но тогда badge bit-perfect гаснет (§7.3).

### 4.5 Модель состояния плеера

```swift
public enum PlaybackState: Sendable {
    case idle
    case loading(Track)
    case playing(Track)
    case paused(Track)
    case failed(Track, PlaybackError)
}

public struct OutputStatus: Sendable {
    let deviceName: String
    let deviceSampleRate: Double      // что реально выставлено на устройстве
    let sourceSampleRate: Double      // что в файле
    let sourceBitDepth: Int
    let isExclusive: Bool             // hog mode получен
    let isBitPerfect: Bool            // вычисляемое: exclusive && rates match && no DSP
    let dsdMode: DSDMode?
}
```

`isBitPerfect` — единственный источник правды для индикатора в UI. Он не должен «врать в плюс»:
любое сомнение → `false`.

### 4.6 Верификация (обязательная часть поставки)

`Tools/audio-verify` — CLI-утилита, которая:

1. Генерирует набор тестовых файлов: синус 1 кГц и белый шум на 44.1/48/88.2/96/176.4/192 кГц,
   16 и 24 бит, плюс DSD64.
2. Прогоняет их через `PlaybackEngine` с виртуальным устройством-петлёй
   (BlackHole или Aggregate Device), пишет результат в файл.
3. Побитово сравнивает вход и выход, печатает отчёт.

**Acceptance criteria фазы аудио — прохождение этого теста, а не «на слух нормально».**

Дополнительно, ручная проверка: Audio MIDI Setup показывает смену частоты устройства
при переключении треков разной частоты.

---

## 5. Библиотека

### 5.1 Модель данных (GRDB / SQLite)

```sql
-- Источники: локальная папка или Subsonic-сервер
CREATE TABLE source (
    id            TEXT PRIMARY KEY,          -- uuid
    kind          TEXT NOT NULL,             -- 'local' | 'subsonic'
    display_name  TEXT NOT NULL,
    bookmark      BLOB,                      -- security-scoped bookmark (local)
    server_url    TEXT,                      -- subsonic
    username      TEXT,                      -- subsonic; пароль в Keychain
    enabled       INTEGER NOT NULL DEFAULT 1,
    last_scan_at  DATETIME
);

CREATE TABLE artist (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    sort_name   TEXT NOT NULL,
    mbid        TEXT,
    UNIQUE(sort_name)
);

CREATE TABLE album (
    id            INTEGER PRIMARY KEY,
    title         TEXT NOT NULL,
    sort_title    TEXT NOT NULL,
    artist_id     INTEGER REFERENCES artist(id),
    album_artist  TEXT,
    year          INTEGER,
    date          TEXT,                      -- ISO, если известна полная
    mbid          TEXT,
    disc_count    INTEGER,
    cover_hash    TEXT,                      -- имя файла в кэше обложек
    is_compilation INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE track (
    id             INTEGER PRIMARY KEY,
    source_id      TEXT NOT NULL REFERENCES source(id) ON DELETE CASCADE,
    remote_id      TEXT,                     -- id на Subsonic-сервере
    relative_path  TEXT,                     -- путь внутри source (local)
    file_size      INTEGER,
    modified_at    DATETIME,
    title          TEXT NOT NULL,
    artist_id      INTEGER REFERENCES artist(id),
    album_id       INTEGER REFERENCES album(id),
    track_no       INTEGER,
    disc_no        INTEGER,
    duration       REAL NOT NULL,
    codec          TEXT NOT NULL,            -- 'flac' | 'alac' | 'dsf' | ...
    sample_rate    INTEGER NOT NULL,
    bit_depth      INTEGER,
    channels       INTEGER NOT NULL,
    bitrate        INTEGER,
    replaygain_track REAL,
    replaygain_album REAL,
    added_at       DATETIME NOT NULL,
    unavailable    INTEGER NOT NULL DEFAULT 0,  -- D-004: файл пропал, трек жив
    cue_start      REAL,                     -- D-013: границы внутри общего
    cue_end        REAL,                     --        файла (рип с CUE)
    UNIQUE(source_id, remote_id)
);

-- Путь уникален для обычных треков и различает дорожки CUE по началу
-- сегмента: у обычного трека coalesce даёт общий −1 (миграция v3).
CREATE UNIQUE INDEX idx_track_path
    ON track(source_id, relative_path, coalesce(cue_start, -1));

CREATE TABLE playlist (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    created_at  DATETIME NOT NULL,
    updated_at  DATETIME NOT NULL,
    is_smart    INTEGER NOT NULL DEFAULT 0,
    rules_json  TEXT                         -- для smart-плейлистов, v2
);

CREATE TABLE playlist_item (
    playlist_id INTEGER NOT NULL REFERENCES playlist(id) ON DELETE CASCADE,
    track_id    INTEGER NOT NULL REFERENCES track(id) ON DELETE CASCADE,
    position    INTEGER NOT NULL,
    PRIMARY KEY (playlist_id, position)
);

CREATE TABLE play_history (
    id          INTEGER PRIMARY KEY,
    track_id    INTEGER NOT NULL REFERENCES track(id) ON DELETE CASCADE,
    played_at   DATETIME NOT NULL,
    completed   INTEGER NOT NULL,            -- дослушан ли до конца
    duration_played REAL NOT NULL
);

CREATE VIRTUAL TABLE track_fts USING fts5(
    title, artist_name, album_title,
    content='', tokenize='unicode61 remove_diacritics 2'
);
```

Индексы: `track(album_id, disc_no, track_no)`, `track(artist_id)`, `track(added_at DESC)`,
`album(sort_title)`, `album(artist_id, year)`, `play_history(played_at DESC)`.

БД лежит в `~/Library/Application Support/Escapement/library.sqlite`, режим WAL.

### 5.2 Сканирование

- Доступ к папкам — через **security-scoped bookmarks**, сохранённые в `source.bookmark`.
  Приложение не sandboxed, но bookmark всё равно даёт устойчивость к переименованию тома.
- **Инкрементальный скан:** файл перечитывается только если изменились `mtime` или `size`.
- **Наблюдение:** FSEvents на корни источников, дебаунс 2 секунды, скан только изменённых поддеревьев.
- **Параллелизм:** чтение метаданных в `TaskGroup`, конкурентность = `ProcessInfo.activeProcessorCount`,
  запись в БД — одной пачкой через `Database.inTransaction`, батчами по 500 треков.
- **Прогресс:** `AsyncStream<ScanProgress>`, UI показывает ненавязчивую полоску в сайдбаре, не модальное окно.
- **Ошибки:** битый файл не роняет скан, попадает в лог `~/Library/Logs/Escapement/scan.log`
  и в список «Problem files» в настройках.

**Бюджет:** 50 000 треков холодным сканом с SSD — не дольше 4 минут. Повторный скан
без изменений — не дольше 15 секунд.

### 5.3 Метаданные

Чтение через `SFBAudioEngine.AudioFile`. Приоритет полей:

- Исполнитель альбома: `ALBUMARTIST` → `ARTIST` → «Various Artists», если в альбоме >1 артиста
  и есть тег `COMPILATION`.
- Сортировочные имена: `ARTISTSORT`/`ALBUMSORT`, иначе — нормализация (убрать ведущие
  «The », привести к casefold, убрать диакритику).
- Номер диска: если отсутствует — 1.
- ReplayGain: читать, **но не применять** (см. §4.1). Хранить для v2.

### 5.4 Обложки

Порядок поиска: embedded picture → `cover.jpg`/`folder.jpg`/`front.png` рядом с файлами →
Subsonic `getCoverArt` → пусто (плейсхолдер из DesignSystem, не заглушка-иконка Apple).

Кэш: `~/Library/Caches/Escapement/covers/<sha256>.jpg`, три размера (64, 256, 1024 pt @2x),
генерируются лениво при первом запросе. Внешние запросы к Cover Art Archive — только
по явной команде пользователя из контекстного меню альбома, никогда автоматически.

---

## 6. Subsonic / Navidrome

### 6.1 Протокол

OpenSubsonic API, минимальная совместимость с Subsonic API 1.16.1.

Аутентификация: `u` + `t` (md5(password + salt)) + `s` (salt) + `v` + `c=Escapement` + `f=json`.
Пароль хранится **только** в Keychain (`kSecClassInternetPassword`, account = username,
server = host). Не в UserDefaults, не в БД, не в логах.

Используемые эндпоинты:

| Эндпоинт | Назначение |
|---|---|
| `ping` | проверка соединения при сохранении настроек |
| `getArtists`, `getArtist` | дерево артистов |
| `getAlbumList2` (`type=alphabeticalByName`, постранично) | инвентаризация альбомов |
| `getAlbum` | треки альбома с метаданными |
| `getCoverArt` | обложки |
| `stream` (`format=raw`, `maxBitRate=0`) | **обязательно** raw — транскодирование убивает bit-perfect |
| `download` | для полной локальной кэш-копии трека |
| `getPlaylists`, `getPlaylist` | плейлисты сервера (только чтение в v1) |
| `scrobble` | опционально, если сервер это проксирует; выключено по умолчанию |

### 6.2 Стратегия воспроизведения с сервера

Bit-perfect и потоковое воспроизведение плохо совмещаются: движку нужно знать точную
частоту дискретизации **до** старта, а сеть может подвести на середине трека.

Решение: **download-then-play**.

1. По нажатию Play трек скачивается целиком через `download` во временный кэш
   `~/Library/Caches/Escapement/stream/`.
2. Воспроизведение стартует из файла — тем же путём, что и локальный трек.
   Никакой отдельной ветки в аудио-движке.
3. Следующий трек очереди префетчится во время текущего.
4. Кэш — LRU с лимитом `Settings.streamCacheSizeGB` (по умолчанию 8 ГБ).
5. UI на время загрузки показывает состояние `.loading`, а не крутилку поверх всего.

Метаданные сервера синхронизируются в ту же таблицу `track` с `source.kind = 'subsonic'`.
Библиотека для пользователя единая — фильтр по источнику есть, но он не первичен.

### 6.3 Оффлайн

Если сервер недоступен — треки этого источника показываются приглушёнными
и не попадают в очередь при shuffle. Ошибка соединения — одна строка в сайдбаре,
не алерт.

---

## 7. Интерфейс

Полная дизайн-система — в `DESIGN.md`. Здесь только функциональные требования.

### 7.1 Окна

- **Главное окно.** Три колонки: сайдбар (источники/навигация) → список (альбомы или треки) →
  детали (текущий альбом). Нижняя панель транспорта на всю ширину.
  Скрытый titlebar (`.windowStyle(.hiddenTitleBar)`), контент под ним.
- **Mini player.** Отдельное окно `240×80`, always-on-top опционально, показывает обложку,
  название, транспорт. Вызов: `⌘⌥M`.
- **Настройки.** Стандартный `Settings` scene, вкладки: Library, Audio, Server, Keys.

### 7.2 Навигация

Сайдбар: `Now Playing` · `Albums` · `Artists` · `Tracks` · `Recently Added` · `Playlists` · источники.

Поиск: `⌘F` фокусирует единственное поле поиска, работает по FTS5, результаты
группируются (Artists / Albums / Tracks), навигация стрелками, Enter — играть, `⌘Enter` — в очередь.

### 7.3 Индикатор качества — ключевой элемент

В транспортной панели, справа от таймингов, постоянно виден технический badge:

```
FLAC 24/192   ·   Exclusive   ·   RME ADI-2
```

Правила отображения:

- Badge в **акцентном цвете**, если `OutputStatus.isBitPerfect == true`.
- Badge в **приглушённом цвете** с зачёркнутым «Exclusive», если hog mode не получен.
- Если частота ресемплится — вместо цифр показывать `192 → 96` в цвете предупреждения.
- Клик по badge открывает поповер с полным состоянием тракта: устройство, доступные частоты,
  что выставлено, причина деградации, если она есть.

Это не украшение. Это единственный способ увидеть, что контракт §4 соблюдается.

### 7.4 Где нужен AppKit

SwiftUI не тянет и требуется `NSViewRepresentable` / прямая работа с AppKit:

- Виртуализированный список на 100k строк с плавным скроллом → `NSTableView`.
  (SwiftUI `List` проверить на реальном объёме; если укладывается в бюджет §12 — оставить SwiftUI.)
- Drag & drop файлов и треков между плейлистами.
- Глобальные горячие клавиши (`NSEvent.addGlobalMonitorForEvents` + Accessibility permission,
  запрашивать только при включении функции).
- Кастомный mini-player window (`NSPanel`, `.nonactivatingPanel`).

### 7.5 Системная интеграция

- `MPNowPlayingInfoCenter` — заполнять полностью, включая обложку.
- `MPRemoteCommandCenter` — play/pause/next/previous, поддержка медиа-клавиш клавиатуры.
- Меню-бар: опциональная иконка с текущим треком и транспортом.
- Dock: badge не используем; прогресс воспроизведения в иконке — нет.

### 7.6 Горячие клавиши

| Комбинация | Действие |
|---|---|
| `Space` | Play / Pause |
| `⌘→` / `⌘←` | Следующий / предыдущий трек |
| `→` / `←` | Перемотка ±5 с |
| `⌘F` | Поиск |
| `⌘⌥M` | Mini player |
| `⌘L` | Показать текущий трек в библиотеке |
| `⌘⇧N` | Новый плейлист |
| `⌘R` | Пересканировать активный источник |
| `⌘,` | Настройки |

---

## 8. Настройки

Хранение: `UserDefaults` через `@AppStorage`-обёртки в типизированной структуре `Settings`.
Пароли — только Keychain.

**Library:** источники (добавить/удалить папку), автоскан при запуске, наблюдение через FSEvents,
список проблемных файлов.

**Audio:** устройство вывода (или «системное по умолчанию»), exclusive access (вкл/выкл),
задержка при смене частоты, поведение при отсутствии точной частоты
(ближайшая кратная / кросс-семейный ресемплинг / отказ), режим DSD, ReplayGain (v1: только «off»,
селектор задизейблен с пояснением).

**Server:** URL, логин, пароль, кнопка Test connection с явным результатом, размер кэша,
кнопка очистки кэша.

**Keys:** переопределение горячих клавиш, включение глобальных медиа-клавиш.

---

## 9. Обработка ошибок

Никаких модальных алертов, кроме двух случаев: удаление источника и очистка библиотеки.

Всё остальное — inline-состояния:

- Не найден файл трека → строка приглушена, иконка-предупреждение, тултип с путём.
- Устройство отключено во время игры → пауза, badge краснеет, текст «output device lost».
  Автовозобновление при возврате устройства — **не делаем**, это опасно для ушей.
- Сервер недоступен → строка источника в сайдбаре приглушена.
- Ошибка декодирования → пропуск трека, запись в лог, счётчик ошибок в настройках.

Логирование: `OSLog` с подсистемой `com.dikairos.escapement`, категории `audio`, `library`,
`network`, `ui`. Уровень `.debug` только в DEBUG-сборке. В логи не попадают пароли, токены,
полные пути к пользовательским файлам в release.

---

## 10. Конкурентность

Swift 6, strict concurrency complete. Правила:

- `Player` — `actor`. Публичный API асинхронный.
- Состояние для UI — `@Observable` класс `PlayerViewModel`, `@MainActor`, подписан на
  `AsyncStream` от `Player`.
- Аудио-callback (real-time thread) — **зона без блокировок**: никаких `os_unfair_lock`,
  аллокаций, Swift-рантайма с возможным ретейном, логирования, обращений к БД.
  Обмен с ним — только через lock-free ring buffer / атомики. Это в основном
  ответственность SFBAudioEngine, но любой собственный код в тракте обязан соблюдать правило.
- Доступ к БД — через `DatabasePool` GRDB, чтение конкурентно, запись сериализована.
- UI-обновления от `ValueObservation` GRDB приходят на MainActor.

---

## 11. Тестирование

| Уровень | Что покрываем |
|---|---|
| Unit | нормализация тегов, сортировочные имена, парсинг Subsonic-ответов, LRU-кэш, логика выбора sample rate |
| Integration | сканер на фикстуре из ~200 файлов разных форматов (генерируются скриптом), миграции БД |
| Audio | `Tools/audio-verify` — побитовое сравнение (§4.6) |
| Performance | XCTest measure: скан 10k треков, поиск по FTS5 на 100k, скролл-бюджет |
| Manual checklist | `docs/manual-checklist.md` — смена частоты в Audio MIDI Setup, отключение DAC на ходу, gapless на живом альбоме, DSD |

Тестовые аудиофайлы генерируются скриптом (`Tools/make-fixtures.sh`, ffmpeg),
в репозиторий не коммитятся.

---

## 12. Бюджеты производительности

Не «желательно», а критерии приёмки:

| Метрика | Порог |
|---|---|
| Холодный старт до интерактивного окна | < 800 мс |
| Отклик Play → первый сэмпл (локальный файл) | < 150 мс (без учёта паузы смены частоты) |
| Скролл списка на 100k треков | 120 fps, без пропусков кадров |
| Поиск FTS5 на 100k треков | < 50 мс до отрисовки результатов |
| Память в покое с библиотекой 50k | < 250 МБ |
| CPU при воспроизведении FLAC 24/96 | < 3% на M-series |
| Пропуски звука (dropouts) за 8 часов | 0 |

---

## 13. Приватность и безопасность

- Ноль исходящих соединений, кроме настроенного Subsonic-сервера.
- Cover Art Archive — только по явному действию пользователя.
- Автообновление: Sparkle по фиду `Di-kairos/rubis-releases` (D-005) — единственная
  фоновая сетевая активность помимо настроенного сервера.
- Пароли в Keychain. Bookmark'и — в БД, они не секрет.
- Entitlements: минимальные. Sandbox выключен (нужен произвольный доступ к дискам,
  включая внешний SSD). Hardened runtime включён.
- Логи не содержат ПД.

---

## 14. Дистрибуция

Сборка для себя: `xcodebuild -scheme Escapement -configuration Release`,
подпись Development-сертификатом или ad-hoc.

Все идентификаторы вынесены в `Config/Escapement.xcconfig`:

```
PRODUCT_NAME = Escapement
PRODUCT_BUNDLE_IDENTIFIER = com.dikairos.escapement
MARKETING_VERSION = 0.1.0
DEVELOPMENT_TEAM =
```

Переименование продукта = правка одного файла.

---

## 15. Открытые вопросы к владельцу

Агент должен спросить, а не решать сам, если упрётся:

1. Конкретная модель ЦАП/интерфейса — от неё зависит, нужен ли DoP и какие частоты тестировать.
2. Где физически лежит библиотека (внутренний SSD / внешний том) — влияет на политику
   bookmark'ов и на поведение при отключении тома.
3. Нужен ли Navidrome прямо в v1 или сначала только локальная библиотека.
