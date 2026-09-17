import AppKit
import EscapementCore
import Foundation
import MusicLibrary
import Observation
import PlaybackEngine
import SubsonicKit
import SwiftUI

/// Composition root (SPEC §3.1): the only place where packages meet.
@MainActor
@Observable
final class AppEnvironment {
    let db: AppDatabase
    let player: Player
    let devices: AudioDeviceController
    let scanner: LibraryScanner
    let covers: CoverCache
    /// Журнал исходящих соединений (SPEC §1.2): один на приложение, чтобы
    /// в панели сходились все запросы — и заметки, и проверки обновлений.
    let networkLedger = NetworkLedger(fileURL: AppEnvironment.ledgerURL)
    /// История прослушиваний (фишка E): файл рядом с журналом соединений —
    /// схема БД после фазы 2 не меняется, и наружу история не уходит.
    let listeningHistory = ListeningHistory(fileURL: AppEnvironment.historyURL)
    /// Аннотации альбомов (D-008): Wikipedia → Claude, кеш на диске.
    let albumInfo: AlbumInfoService
    /// Треки с сервера: скачивание в кэш и префетч (SPEC §6.2).
    let remote: RemotePlayback

    static var ledgerURL: URL {
        supportDirectory.appendingPathComponent("network-ledger.json")
    }

    static var historyURL: URL {
        supportDirectory.appendingPathComponent("listening-history.json")
    }

    private static var supportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Escapement")
    }

    var trackRepo: TrackRepository { TrackRepository(db: db) }
    var albumRepo: AlbumRepository { AlbumRepository(db: db) }
    var artistRepo: ArtistRepository { ArtistRepository(db: db) }
    var sourceRepo: SourceRepository { SourceRepository(db: db) }
    var playlistRepo: PlaylistRepository { PlaylistRepository(db: db) }

    // MARK: - Playback state mirrored for SwiftUI

    private(set) var playbackState: PlaybackState = .idle
    private(set) var outputStatus: OutputStatus?
    private(set) var scanProgress: ScanProgress?
    /// Режимы порядка переживают перезапуск отдельно от очереди — как в Music.app (D-020).
    private(set) var repeatMode =
        UserDefaults.standard.string(forKey: ModeKey.repeatMode).flatMap(RepeatMode.init) ?? .off
    private(set) var shuffleMode =
        UserDefaults.standard.string(forKey: ModeKey.shuffleMode).flatMap(ShuffleMode.init) ?? .off
    private enum ModeKey {
        static let repeatMode = "playback.repeatMode"
        static let shuffleMode = "playback.shuffleMode"
    }
    /// Счётчик изменений очереди. Нужен экранам: очередь меняется и без смены
    /// состояния воспроизведения — тихое восстановление при запуске оставляет
    /// `playbackState` в `idle`, и подписка на трек ничего бы не заметила.
    private(set) var queueRevision = 0
    /// Счётчик изменений библиотеки: скан, синхронизация, смена источников.
    /// Разделы без живого наблюдения БД (Tracks, Artists, Recently Added,
    /// Playlists) перечитываются по нему, а не остаются с прошлым снимком.
    private(set) var libraryRevision = 0
    /// Счётчик записей истории: открытый History перечитывается по нему, а не
    /// только при появлении.
    private(set) var historyRevision = 0
    /// FSEvents по корням локальных источников (SPEC §5.2): изменение папки
    /// запускает скан её источника само, без ⌘R.
    private var folderWatcher: FolderWatcher?
    /// Источники, которые сканируются прямо сейчас, и те, кому за это время
    /// пришёл повторный запрос. Актор сканера не запрещает два скана одного
    /// источника вперемешку между `await` — сериализуем здесь.
    private var scanning: Set<String> = []
    private var rescanPending: Set<String> = []
    /// Трек, который уже перезапускали после сорванной загрузки.
    private var lastRemoteRetry: Int64?
    /// Серверы, которые не отвечают (SPEC §6.3).
    private(set) var offlineServers: Set<String> = []
    /// Строка о молчащем сервере для сайдбара — одна строка, не алерт.
    private(set) var serverStatus: String?
    /// Папки, чей последний скан упал (закладка не резолвится, папку убрали):
    /// id → имя. Без этого ошибка оставалась только в логе.
    private var unreadableSources: [String: String] = [:]
    /// Строка о нечитаемой папке для сайдбара — как `serverStatus`, не алерт.
    var sourceStatus: String? { Self.sourceStatus(unreadable: unreadableSources) }

    nonisolated static func sourceStatus(unreadable: [String: String]) -> String? {
        switch unreadable.count {
        case 0: nil
        case 1: "\(unreadable.values.first ?? "") can't be read — add the folder again"
        default: "\(unreadable.count) folders can't be read — add them again"
        }
    }

    // MARK: - Search (SPEC §7.2)

    var searchText = ""
    /// Инкремент по ⌘F — Sidebar фокусирует поле.
    var searchFocusTrigger = 0
    /// Инкремент по ↓ в поле поиска — фокус уходит в список результатов.
    var searchResultsFocusTrigger = 0

    // MARK: - Ввод текста

    /// В поле поиска стоит курсор.
    var searchFieldFocused = false
    /// Переименование плейлиста — открыт TextField.
    var renamingPlaylist = false

    /// Пока пользователь печатает, глобальные горячие клавиши без модификаторов
    /// (`Space`, `←`, `→`) отключаются: как пункты меню они перехватывают событие
    /// раньше текстового поля, и в поиск было бы не набрать пробел.
    var isEditingText: Bool { searchFieldFocused || renamingPlaylist }

    /// Свежесозданный по ⌘⇧N плейлист: MainWindow переключает раздел,
    /// PlaylistsView открывает его и сразу даёт переименовать.
    var pendingPlaylistId: Int64?

    /// Инкремент по ⌘L — MainWindow открывает альбом играющего трека.
    var revealCurrentTrigger = 0

    /// Глобальные медиа-клавиши. Объект инертен: монитор ставится только
    /// когда функцию включили в настройках.
    private(set) var globalMediaKeys: GlobalMediaKeys?
    /// Пробел и стрелки достаются текстовому полю, а не меню, пока в нём
    /// стоит курсор — по первому ответчику окна, без флагов на каждое поле.
    private let textFieldKeyGuard = TextFieldKeyGuard()

    init() throws {
        #if DEBUG
        // Прогон на синтетической библиотеке (замер скролла на 100k):
        // RUBIS_DB_PATH=/tmp/rubis-100k/library.sqlite — фикстуру пишет
        // тест `generateLargeLibraryFixture` в MusicLibrary.
        if let path = ProcessInfo.processInfo.environment["RUBIS_DB_PATH"] {
            db = try AppDatabase(path: path)
        } else {
            db = try AppDatabase.standard()
        }
        #else
        db = try AppDatabase.standard()
        #endif
        devices = AudioDeviceController()
        player = Player(devices: devices)
        covers = try CoverCache()
        scanner = LibraryScanner(db: db, covers: covers)
        albumInfo = AlbumInfoService(ledger: networkLedger)
        let cacheLimitGB =
            UserDefaults.standard.object(forKey: SettingsKey.streamCacheSizeGB) as? Int
            ?? SettingsKey.defaultStreamCacheSizeGB
        remote = RemotePlayback(
            cache: try StreamCache(
                limitBytes: Int64(max(1, cacheLimitGB)) * 1024 * 1024 * 1024,
                // Ответ сервера становится записью кэша, только если он
                // открывается тем же декодером, что будет играть.
                validate: { url in try AudioProbe.validate(url) }),
            ledger: networkLedger)

        Task { [player] in
            for await state in await player.stateStream() {
                self.playbackState = state
                // Пауза, стоп, ошибка: прослушанное к этому моменту — в историю.
                if case .playing = state {} else { self.flushListening() }
                if case .playing = state {
                    self.lastRemoteRetry = nil
                    await self.saveQueueSnapshot()
                    // Префетч — сетевая загрузка целого файла; в этом цикле
                    // она задерживала бы `.paused`/`.failed` до конца скачивания.
                    self.prefetchTask?.cancel()
                    self.prefetchTask = Task { await self.prefetchNext() }
                }
                if case .failed(let track, _) = state { await self.retryRemote(track) }
            }
        }
        Task { await registerServers() }
        globalMediaKeys = GlobalMediaKeys(env: self)
        // Настройки Audio живут в UserDefaults, но до этого применялись только
        // при открытии Settings — плеер стартовал с дефолтным конфигом и терял
        // выбранный выход. Толкаем сохранённый конфиг сразу.
        Task { [player] in await player.update(configuration: Self.storedAudioConfiguration()) }
        Task { await restoreQueue() }
        // Позиция внутри трека нигде больше не хранится — пишем её раз в
        // секунду, чтобы ⌘Q в любой момент терял не больше секунды. Тот же
        // тик считает прослушанное для истории.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.tick()
            }
        }
        Task { [player] in
            for await status in await player.statusStream() {
                self.outputStatus = status
            }
        }
        rebuildFolderWatcher()
        // Последние секунды прослушивания — в историю до выхода.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushListening() }
        }
    }

    /// Источники добавили или убрали: наблюдатели папок — заново, разделы —
    /// перечитать.
    func sourcesDidChange() {
        rebuildFolderWatcher()
        libraryRevision += 1
    }

    /// Наблюдение за корнями локальных источников. Изменение внутри корня
    /// (с дебаунсом watcher'а) — скан именно этого источника.
    private func rebuildFolderWatcher() {
        folderWatcher?.stop()
        folderWatcher = nil
        guard let sources = try? sourceRepo.all() else { return }
        var roots: [(url: URL, source: Source)] = []
        for source in sources where source.kind == .local && source.enabled {
            guard let bookmark = source.bookmark,
                let url = try? LibraryScanner.resolveBookmark(bookmark)
            else { continue }
            roots.append((url, source))
        }
        guard !roots.isEmpty else { return }
        folderWatcher = FolderWatcher(roots: roots.map(\.url)) { [weak self] changed in
            guard let self else { return }
            let touched = roots.filter { root in
                changed.contains { $0.path.hasPrefix(root.url.path) }
            }
            for root in touched {
                Task { await self.rescanQuietly(source: root.source) }
            }
        }
    }

    private func rescanQuietly(source: Source) async {
        do {
            try await rescan(source: source)
        } catch {
            Log.library.error("watched rescan failed: \(Log.describe(error), privacy: .public)")
        }
    }

    // MARK: - Intents

    /// Плей всего альбома с выбранной позиции; `nil` — с первого доступного.
    func play(album: Album, startAt index: Int? = nil) {
        guard let albumId = album.id else { return }
        Task {
            guard let tracks = try? trackRepo.tracks(inAlbum: albumId) else { return }
            play(tracks: tracks, startAt: index)
        }
    }

    /// Текущая загрузка следующего трека. Новый `.playing` отменяет прежнюю:
    /// она относилась к прежней очереди.
    private var prefetchTask: Task<Void, Never>?

    /// Актуальность пользовательских команд транспорта. Отметка берётся ДО сети,
    /// проверяется после загрузки: иначе докачавшийся A запускался поверх более
    /// нового Play B или уже нажатого Stop (R02).
    private let transport = TransportCommands()

    /// Очередь изменилась: экраны перечитывают, снимок пишется сразу — иначе
    /// enqueue на паузе не переживал бы перезапуск.
    private func queueDidChange() async {
        queueRevision += 1
        await saveQueueSnapshot()
    }

    /// Плей произвольного списка треков с позиции.
    /// `index` — трек, выбранный пользователем; `nil` — «играть всё» с первого
    /// доступного.
    func play(tracks: [Track], startAt index: Int? = nil) {
        let items = resolveItems(tracks: tracks)
        // Часть треков могла отвалиться (нет файла) — стартовая позиция ищется
        // по самому треку, а не по индексу исходного списка.
        let start: Int
        if let index {
            // Выбранный трек выпал (серый, файла нет) — не играем ничего: чужой
            // первый доступный вместо выбранного сбивает с толку (#28).
            let target = tracks.indices.contains(index) ? tracks[index].id : nil
            guard let found = items.firstIndex(where: { $0.track.id == target }) else { return }
            start = found
        } else {
            guard !items.isEmpty else { return }
            start = 0
        }
        // Отметка — здесь, синхронно: пауза или Next, нажатые до старта задачи,
        // должны её обесценить (F04).
        let token = transport.begin()
        Task {
            await transport.run(
                token,
                load: { await self.fetchIfRemote(items[start].track) },
                act: {
                    await self.player.play(items: items, startAt: start)
                    await self.queueDidChange()
                })
        }
    }

    /// Треки сразу после текущего.
    func playNext(tracks: [Track]) {
        let items = resolveItems(tracks: tracks)
        guard !items.isEmpty else { return }
        Task {
            await player.playNext(items: items)
            await queueDidChange()
        }
    }

    /// Треки в конец очереди.
    func addToQueue(tracks: [Track]) {
        let items = resolveItems(tracks: tracks)
        guard !items.isEmpty else { return }
        Task {
            await player.enqueue(items: items)
            await queueDidChange()
        }
    }

    /// Текущая очередь для экрана Now Playing: состав и индекс играющего.
    func queueSnapshot() async -> (tracks: [Track], index: Int) {
        let items = await player.queuedItems()
        return (items.map(\.track), await player.currentIndex())
    }

    /// Прыжок на трек внутри текущей очереди (двойной клик в Now Playing).
    func playQueueItem(at index: Int) {
        let token = transport.begin()
        Task {
            let items = await player.queuedItems()
            guard items.indices.contains(index) else { return }
            await transport.run(
                token,
                load: { await self.fetchIfRemote(items[index].track) },
                act: {
                    await self.player.play(items: items, startAt: index)
                    await self.queueDidChange()
                })
        }
    }

    /// Конфиг аудио-тракта из UserDefaults — единственный маппинг ключей
    /// настроек в AudioConfiguration (используют и старт, и вкладка Audio).
    static func storedAudioConfiguration() -> AudioConfiguration {
        let defaults = UserDefaults.standard
        let uid = defaults.string(forKey: "preferredDeviceUID") ?? ""
        return AudioConfiguration(
            exclusiveAccess: defaults.object(forKey: "exclusiveAccess") as? Bool ?? true,
            sampleRateChangeDelay: .milliseconds(
                defaults.object(forKey: "rateChangeDelayMs") as? Int ?? 300),
            rateFallback: .init(rawValue: defaults.string(forKey: "rateFallback") ?? "")
                ?? .nearestFamilyMultiple,
            dsdMode: .init(rawValue: defaults.string(forKey: "dsdMode") ?? "")
                ?? .dopIfAvailable,
            dopConfirmedDeviceUIDs: Set(
                defaults.stringArray(forKey: SettingsKey.dopConfirmedDeviceUIDs) ?? []),
            preferredDeviceUID: uid.isEmpty ? nil : uid)
    }

    /// Перечитать настройки и толкнуть в плеер (вкладка Audio дёргает на
    /// каждом изменении; действует со следующего трека).
    func applyStoredAudioConfiguration() {
        Task { await player.update(configuration: Self.storedAudioConfiguration()) }
    }

    func cycleShuffleMode() {
        let modes = ShuffleMode.allCases
        let next = modes[(modes.firstIndex(of: shuffleMode).map { $0 + 1 } ?? 0) % modes.count]
        shuffleMode = next
        UserDefaults.standard.set(next.rawValue, forKey: ModeKey.shuffleMode)
        Task {
            await player.setShuffleMode(next)
            await queueDidChange()
        }
    }

    func cycleRepeatMode() {
        let modes = RepeatMode.allCases
        let next = modes[(modes.firstIndex(of: repeatMode).map { $0 + 1 } ?? 0) % modes.count]
        repeatMode = next
        UserDefaults.standard.set(next.rawValue, forKey: ModeKey.repeatMode)
        Task { await player.setRepeatMode(next) }
    }

    func togglePlayPause() {
        switch playbackState {
        case .loading:
            cancelLoading()
        case .failed:
            retryCurrent()
        default:
            // Пауза и Stop — тоже команды транспорта: начатая загрузка больше не актуальна.
            transport.invalidate()
            Task { await player.togglePlayPause() }
        }
    }

    /// Главная кнопка следует состоянию: загрузку отменяет, ошибку повторяет (#28).
    var playButton: (icon: String, label: String) {
        switch playbackState {
        case .playing: ("pause.fill", "Pause")
        case .loading: ("xmark", "Cancel")
        case .failed: ("arrow.clockwise", "Retry")
        default: ("play.fill", "Play")
        }
    }

    /// Play во время загрузки — «Cancel», как в Music.app: загрузка обесценена,
    /// плеер остановлен, экран не висит на «Loading…» (#28).
    func cancelLoading() {
        transport.invalidate()
        Task {
            await player.stop()
            playbackState = .idle
        }
    }

    /// Play после ошибки — «Retry»: тот же трек заново; битый файл сервера
    /// выбрасывается из кэша, чтобы повтор не открыл его снова (#28).
    func retryCurrent() {
        guard case .failed(let track, _) = playbackState else { return }
        lastRemoteRetry = nil
        Task {
            await remote.invalidate(track)
            playQueueItem(at: await player.currentIndex())
        }
    }

    /// Перемотка относительно текущей позиции (SPEC §7.6: →/← ±5 с).
    func seek(by seconds: Double) {
        Task {
            if let time = await player.playbackTime() {
                await player.seek(to: max(0, min(time.total, time.current + seconds)))
            }
        }
    }

    /// ⌘L: раздел Albums + альбом играющего трека.
    func revealCurrentTrack() {
        revealCurrentTrigger += 1
    }

    /// Трек, который сейчас играет или на паузе.
    var currentTrack: Track? {
        switch playbackState {
        case .playing(let track), .paused(let track), .loading(let track):
            return track
        default:
            return nil
        }
    }

    // MARK: - Queue persistence (продолжение с места остановки)

    /// Снимок очереди: состав, индекс и позиция внутри трека. Пишется на
    /// каждом изменении очереди и на каждом старте; тик дописывает прогресс.
    private func saveQueueSnapshot() async {
        let (items, order) = await player.queueOrder()
        let ids = items.compactMap { $0.track.id }
        let snapshot = PlaybackSnapshot(
            // Трек без id сбил бы перестановку — тогда порядок не сохраняется.
            trackIds: ids, order: ids.count == items.count ? order : nil,
            index: await player.currentIndex(),
            offset: await player.playbackTime()?.current ?? 0)
        snapshot.save(to: .standard)
    }

    /// Прогресс — раз в секунду. Индекс идёт вместе с позицией, иначе они
    /// разъезжаются на переходе трека. Пауза тоже сохраняется: закрыть плеер
    /// на паузе и вернуться туда же — нормальное ожидание.
    private func tick() async {
        switch playbackState {
        case .playing(let track), .paused(let track):
            guard let time = await player.playbackTime() else { return }
            PlaybackSnapshot.saveProgress(
                index: await player.currentIndex(), offset: time.current, to: .standard)
            // На паузе секунды не капают: слушают только то, что звучит.
            if case .playing = playbackState {
                countListening(track: track, position: time.current)
            }
        default:
            return
        }
    }

    // MARK: - История прослушиваний (фишка E)

    /// Текущее проигрывание: сколько секунд уже прозвучало, засчитано ли оно
    /// (и когда — по этой отметке событие потом дописывается) и сколько
    /// секунд история уже знает.
    private var listening:
        (trackId: Int64, seconds: Double, position: Double, recordedAt: Date?, flushed: Double)?

    /// Прослушивание засчитывается один раз за проигрывание. Прыжок назад по
    /// таймлайну (повтор трека, перемотка в начало) начинает счёт заново —
    /// иначе repeat-one за вечер дал бы одну запись.
    private func countListening(track: Track, position: Double) {
        guard let id = track.id else { return }
        if var state = listening, state.trackId == id, position >= state.position - 2 {
            state.seconds += 1
            state.position = position
            listening = state
        } else {
            flushListening()
            listening = (id, 1, position, nil, 0)
        }
        guard var state = listening else { return }
        if state.recordedAt == nil,
            ListeningHistory.counts(listened: state.seconds, duration: track.duration)
        {
            let stamp = Date()
            state.recordedAt = stamp
            state.flushed = state.seconds
            listening = state
            record(play: track, seconds: state.seconds, at: stamp)
        } else if state.recordedAt != nil, Int(state.seconds) % 30 == 0 {
            // Секунды капают в историю по ходу, а не только на смене трека:
            // ⌘Q посреди длинной вещи теряет не больше полминуты.
            flushListening()
        }
    }

    /// Дописать засчитанному событию всё, что прозвучало после порога.
    private func flushListening() {
        guard let state = listening, let recordedAt = state.recordedAt,
            state.seconds > state.flushed
        else { return }
        listening?.flushed = state.seconds
        Task { [listeningHistory] in
            await listeningHistory.extend(
                trackId: state.trackId, recordedAt: recordedAt, seconds: state.seconds)
            historyRevision += 1
        }
    }

    /// Имена артиста и альбома снимаются один раз на засчитанное
    /// прослушивание и уезжают в историю строками — она не должна ломаться
    /// от пересканирования библиотеки.
    private func record(play track: Track, seconds: Double, at stamp: Date) {
        guard let id = track.id else { return }
        let artist = track.artistId.flatMap { try? artistRepo.artist(id: $0) }?.name ?? ""
        let album = track.albumId.flatMap { try? albumRepo.album(id: $0) }?.title ?? ""
        Task { [listeningHistory, title = track.title] in
            await listeningHistory.record(
                trackId: id, title: title, artist: artist, album: album, seconds: seconds,
                date: stamp)
            historyRevision += 1
        }
    }

    /// Восстановление очереди при запуске: состав, индекс и позиция — без звука.
    /// Первый Play продолжит трек с той же секунды.
    private func restoreQueue() async {
        guard let stored = PlaybackSnapshot.load(from: .standard),
            let tracks = try? trackRepo.tracks(ids: stored.trackIds)
        else {
            await player.setShuffleMode(shuffleMode)
            await player.setRepeatMode(repeatMode)
            return
        }
        var items = resolveItems(tracks: tracks)
        // Часть треков могла выпасть (файл пропал, источник отключён): порядок и
        // индекс переносятся на выживших, секунда выпавшего чужому не достаётся.
        let survivors = Set(items.compactMap { $0.track.id })
        var snapshot = stored.keeping(survivors.contains)
        #if DEBUG
        // Снимки вёрстки: ad-hoc сборка не резолвит bookmark подписанного
        // релиза, и очередь оказывается пустой. `RUBIS_FAKE_QUEUE=1` наполняет
        // её теми же треками с несуществующими путями — звука нет (restore не
        // играет), а экран рисуется целиком.
        if items.isEmpty, ProcessInfo.processInfo.environment["RUBIS_FAKE_QUEUE"] != nil {
            items = tracks.map {
                PlaybackItem(track: $0, url: URL(fileURLWithPath: $0.relativePath ?? "/dev/null"))
            }
            snapshot = PlaybackSnapshot(
                trackIds: tracks.compactMap(\.id), index: stored.index, offset: 0)
        }
        #endif
        guard !items.isEmpty else {
            await player.setShuffleMode(shuffleMode)
            await player.setRepeatMode(repeatMode)
            return
        }
        await player.restore(
            items: items, order: snapshot.order, at: snapshot.index, offset: snapshot.offset,
            shuffleMode: shuffleMode, repeatMode: repeatMode)
        queueRevision += 1
    }

    func next() {
        transport.invalidate()
        Task { await player.next() }
    }

    func previous() {
        transport.invalidate()
        Task { await player.previous() }
    }

    func seek(to fraction: Double) {
        Task {
            if let time = await player.playbackTime() {
                await player.seek(to: time.total * fraction)
            }
        }
    }

    /// Track → PlaybackItem: резолв URL через bookmark источника.
    private func resolveItems(tracks: [Track]) -> [PlaybackItem] {
        guard let sources = try? sourceRepo.all() else { return [] }
        let roots: [String: URL] = Dictionary(
            uniqueKeysWithValues: sources.compactMap { source in
                guard let bookmark = source.bookmark,
                    let url = try? LibraryScanner.resolveBookmark(bookmark)
                else { return nil }
                return (source.id, url)
            })
        return tracks.compactMap { track in
            // Пропавшие файлы не попадают в очередь (SPEC §9) — играем остальное.
            guard !track.unavailable else { return nil }
            // Серверный трек встаёт в очередь адресом в кэше: файла там может
            // ещё не быть — его дотащит `fetch` перед стартом или префетч.
            if RemotePlayback.isRemote(track) {
                return remote.location(for: track).map { PlaybackItem(track: track, url: $0) }
            }
            guard let root = roots[track.sourceId], let relative = track.relativePath
            else {
                return nil
            }
            return PlaybackItem(track: track, url: root.appendingPathComponent(relative))
        }
    }

    // MARK: - Треки с сервера (SPEC §6.2)

    /// Клиенты серверов собираются один раз за запуск — иначе связка ключей
    /// опрашивалась бы на каждый трек.
    private func registerServers() async {
        guard let sources = try? sourceRepo.all() else { return }
        for source in sources where source.kind == .subsonic {
            await remote.register(source: source)
            await checkServer(source)
        }
    }

    /// Сервер молчит — его треки приглушаются и выпадают из очереди и shuffle
    /// (SPEC §6.3). Тот же флаг, что у пропавших файлов, поэтому отдельного
    /// оформления не нужно; в сайдбаре — строка, не алерт.
    func checkServer(_ source: Source) async {
        let reachable = await remote.isReachable(sourceId: source.id)
        let changed = (try? trackRepo.setUnavailable(!reachable, inSource: source.id)) ?? 0
        offlineServers =
            reachable
            ? offlineServers.subtracting([source.id])
            : offlineServers.union([source.id])
        serverStatus = offlineServers.isEmpty ? nil : "\(source.displayName) is offline"
        // Списки читают библиотеку наблюдением, а очередь — нет: она собрана
        // из старых строк и всё ещё считает молчащие треки играбельными.
        if changed > 0 {
            queueRevision += 1
            libraryRevision += 1
        }
    }

    /// Файл трека до старта: локальный уже на месте, серверный качается.
    /// На время загрузки экран показывает `.loading` — так же, как движок
    /// показывает подготовку устройства.
    private func fetchIfRemote(_ track: Track) async {
        guard RemotePlayback.isRemote(track) else { return }
        playbackState = .loading(track)
        await remote.fetch(track)
    }

    /// Следующий трек очереди качается, пока играет текущий. Когда файл лёг,
    /// плеер пробует склеить стык заново: в момент старта текущего трека
    /// склеивать было нечего.
    private func prefetchNext() async {
        let items = await player.queuedItems()
        let next = await player.currentIndex() + 1
        guard items.indices.contains(next), RemotePlayback.isRemote(items[next].track) else {
            return
        }
        // Префетч длится через сеть: за это время очередь и текущий трек могли
        // смениться, и склеивать было бы уже не тот стык.
        let token = transport.current()
        let fetched = items[next].track.id
        guard await remote.fetch(items[next].track) != nil else { return }
        // Склеиваем только если следующим по-прежнему стоит скачанный трек, а
        // не просто «какой-то» под тем же номером.
        let now = await player.queuedItems()
        let upcoming = await player.currentIndex() + 1
        guard transport.isCurrent(token), now.indices.contains(upcoming),
            now[upcoming].track.id == fetched
        else { return }
        await player.rearmGapless()
    }

    /// Сорванный серверный трек: файл не успел приехать к моменту, когда
    /// движок до него дошёл. Качаем и играем ещё раз — но ровно один раз,
    /// иначе мёртвый трек крутил бы петлю.
    private func retryRemote(_ track: Track) async {
        guard RemotePlayback.isRemote(track), track.id != lastRemoteRetry else { return }
        lastRemoteRetry = track.id
        // Повтор тоже проходит через сеть — к его концу пользователь мог уйти
        // на другой трек или остановиться.
        let token = transport.current()
        // Файл мог лежать в кэше и оказаться битым — выбрасываем его, иначе
        // повтор снова открыл бы тот же объект.
        await remote.invalidate(track)
        guard await remote.fetch(track) != nil else {
            // Не скачалось со второго раза — скорее всего сервер молчит.
            if let source = try? sourceRepo.all().first(where: { $0.id == track.sourceId }) {
                await checkServer(source)
            }
            return
        }
        guard transport.isCurrent(token) else { return }
        await player.playCurrent()
    }

    // MARK: - Playlists

    func createPlaylist() {
        do {
            pendingPlaylistId = try playlistRepo.create(name: "New Playlist").id
        } catch {
            Log.library.error("create playlist failed: \(error, privacy: .public)")
        }
    }

    /// «Add to Playlist» из контекстного меню трека: дубликаты пропускает
    /// репозиторий, открытый плейлист перечитывается по `libraryRevision`.
    func add(tracks: [Track], to playlist: Playlist) {
        guard let playlistId = playlist.id else { return }
        do {
            try playlistRepo.append(tracks.compactMap(\.id), to: playlistId)
            libraryRevision += 1
        } catch {
            Log.library.error("add to playlist failed: \(error, privacy: .public)")
        }
    }

    /// Новый плейлист сразу с треками — открывается на переименование, как ⌘⇧N.
    func addToNewPlaylist(tracks: [Track]) {
        do {
            let playlist = try playlistRepo.create(name: "New Playlist")
            add(tracks: tracks, to: playlist)
            pendingPlaylistId = playlist.id
        } catch {
            Log.library.error("create playlist failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Library

    func addFolderSource(url: URL) {
        Task {
            do {
                var source = Source(kind: .local, displayName: url.lastPathComponent)
                source.bookmark = try LibraryScanner.makeBookmark(for: url)
                try sourceRepo.upsert(source)
                sourcesDidChange()
                try await rescan(source: source)
            } catch {
                Log.library.error("add source failed: \(error, privacy: .public)")
            }
        }
    }

    /// ⌘R обновляет всё, что подключено: папки сканируются, серверы
    /// синхронизируются — источник для владельца один, «моя музыка».
    func rescanAll() {
        Task {
            guard let sources = try? sourceRepo.all() else { return }
            for source in sources where source.enabled {
                switch source.kind {
                case .local: await rescanQuietly(source: source)
                case .subsonic: await sync(server: source)
                }
            }
        }
    }

    /// Синхронизация одного сервера (фаза 6, pack 3). Ошибка сети не роняет
    /// остальные источники — она остаётся в логе, а полоска гаснет.
    func sync(server source: Source) async {
        guard let client = SubsonicAccount.client(for: source) else {
            Log.library.error("subsonic source without credentials: \(source.id, privacy: .public)")
            return
        }
        // Свежесохранённый сервер играет сразу, без перезапуска приложения.
        await remote.register(source: source)
        let sync = SubsonicSync(
            client: client, sourceId: source.id, db: db, covers: covers, ledger: networkLedger)
        do {
            for try await progress in await sync.run() {
                switch progress {
                case .albums(let done, let total):
                    scanProgress = .reading(done: done, total: total)
                case .finished(let tracks, let removed):
                    Log.library.info(
                        "subsonic sync: +\(tracks, privacy: .public) −\(removed, privacy: .public)")
                }
            }
        } catch {
            Log.library.error("subsonic sync failed: \(Log.describe(error), privacy: .public)")
        }
        scanProgress = nil
        libraryRevision += 1
        // Синхронизация — самый честный ответ на вопрос «сервер жив?»:
        // после неё состояние источника переставляется по факту.
        await checkServer(source)
    }

    /// Скан одного источника — не больше одного за раз. Повторный запрос во
    /// время скана (⌘R дважды, папка меняется под сканом) не накладывается,
    /// а идёт следом. Полоска прогресса гаснет и при ошибке.
    private func rescan(source: Source) async throws {
        guard !scanning.contains(source.id) else {
            rescanPending.insert(source.id)
            return
        }
        scanning.insert(source.id)
        defer {
            scanning.remove(source.id)
            scanProgress = nil
            libraryRevision += 1
        }
        do {
            repeat {
                rescanPending.remove(source.id)
                for try await progress in scanner.scanStream(source: source) {
                    scanProgress = progress
                }
            } while rescanPending.contains(source.id)
            unreadableSources[source.id] = nil
        } catch {
            unreadableSources[source.id] = source.displayName
            throw error
        }
    }
}
