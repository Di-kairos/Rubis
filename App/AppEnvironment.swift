import EscapementCore
import Foundation
import MusicLibrary
import Observation
import PlaybackEngine
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
    private(set) var repeatMode: RepeatMode = .off
    private(set) var shuffleMode: ShuffleMode = .off
    /// Счётчик изменений очереди. Нужен экранам: очередь меняется и без смены
    /// состояния воспроизведения — тихое восстановление при запуске оставляет
    /// `playbackState` в `idle`, и подписка на трек ничего бы не заметила.
    private(set) var queueRevision = 0

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

        Task { [player] in
            for await state in await player.stateStream() {
                self.playbackState = state
                if case .playing = state { await self.saveQueueSnapshot() }
            }
        }
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
    }

    // MARK: - Intents

    /// Плей всего альбома с выбранной позиции.
    func play(album: Album, startAt index: Int = 0) {
        guard let albumId = album.id else { return }
        Task {
            guard let tracks = try? trackRepo.tracks(inAlbum: albumId) else { return }
            play(tracks: tracks, startAt: index)
        }
    }

    /// Плей произвольного списка треков с позиции.
    func play(tracks: [Track], startAt index: Int = 0) {
        let items = resolveItems(tracks: tracks)
        // Часть треков могла отвалиться (нет файла) — стартовая позиция ищется
        // по самому треку, а не по индексу исходного списка.
        let target = tracks.indices.contains(index) ? tracks[index].id : nil
        let start = items.firstIndex { $0.track.id == target } ?? 0
        Task {
            await player.play(items: items, startAt: start)
            queueRevision += 1
        }
    }

    /// Треки сразу после текущего.
    func playNext(tracks: [Track]) {
        let items = resolveItems(tracks: tracks)
        guard !items.isEmpty else { return }
        Task {
            await player.playNext(items: items)
            queueRevision += 1
        }
    }

    /// Треки в конец очереди.
    func addToQueue(tracks: [Track]) {
        let items = resolveItems(tracks: tracks)
        guard !items.isEmpty else { return }
        Task {
            await player.enqueue(items: items)
            queueRevision += 1
        }
    }

    /// Текущая очередь для экрана Now Playing: состав и индекс играющего.
    func queueSnapshot() async -> (tracks: [Track], index: Int) {
        let items = await player.queuedItems()
        return (items.map(\.track), await player.currentIndex())
    }

    /// Прыжок на трек внутри текущей очереди (двойной клик в Now Playing).
    func playQueueItem(at index: Int) {
        Task {
            let items = await player.queuedItems()
            guard items.indices.contains(index) else { return }
            await player.play(items: items, startAt: index)
            queueRevision += 1
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
        Task {
            await player.setShuffleMode(next)
            queueRevision += 1
        }
    }

    func cycleRepeatMode() {
        let modes = RepeatMode.allCases
        let next = modes[(modes.firstIndex(of: repeatMode).map { $0 + 1 } ?? 0) % modes.count]
        repeatMode = next
        Task { await player.setRepeatMode(next) }
    }

    func togglePlayPause() {
        Task { await player.togglePlayPause() }
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

    /// Снимок очереди: состав, индекс и позиция внутри трека.
    /// ponytail: enqueue/playNext без старта не снимаются — снимок догонит
    /// на следующем тике или переходе трека.
    private func saveQueueSnapshot() async {
        let items = await player.queuedItems()
        let snapshot = PlaybackSnapshot(
            trackIds: items.compactMap { $0.track.id },
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

    /// Текущее проигрывание: сколько секунд уже прозвучало и записано ли оно.
    private var listening: (trackId: Int64, seconds: Double, position: Double, recorded: Bool)?

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
            listening = (id, 1, position, false)
        }
        guard var state = listening, !state.recorded,
            ListeningHistory.counts(listened: state.seconds, duration: track.duration)
        else { return }
        state.recorded = true
        listening = state
        record(play: track, seconds: state.seconds)
    }

    /// Имена артиста и альбома снимаются один раз на засчитанное
    /// прослушивание и уезжают в историю строками — она не должна ломаться
    /// от пересканирования библиотеки.
    private func record(play track: Track, seconds: Double) {
        guard let id = track.id else { return }
        let artist = track.artistId.flatMap { try? artistRepo.artist(id: $0) }?.name ?? ""
        let album = track.albumId.flatMap { try? albumRepo.album(id: $0) }?.title ?? ""
        Task { [listeningHistory, title = track.title] in
            await listeningHistory.record(
                trackId: id, title: title, artist: artist, album: album, seconds: seconds)
        }
    }

    /// Восстановление очереди при запуске: состав, индекс и позиция — без звука.
    /// Первый Play продолжит трек с той же секунды.
    private func restoreQueue() async {
        guard let snapshot = PlaybackSnapshot.load(from: .standard),
            let tracks = try? trackRepo.tracks(ids: snapshot.trackIds)
        else { return }
        var items = resolveItems(tracks: tracks)
        #if DEBUG
        // Снимки вёрстки: ad-hoc сборка не резолвит bookmark подписанного
        // релиза, и очередь оказывается пустой. `RUBIS_FAKE_QUEUE=1` наполняет
        // её теми же треками с несуществующими путями — звука нет (restore не
        // играет), а экран рисуется целиком.
        if items.isEmpty, ProcessInfo.processInfo.environment["RUBIS_FAKE_QUEUE"] != nil {
            items = tracks.map {
                PlaybackItem(track: $0, url: URL(fileURLWithPath: $0.relativePath ?? "/dev/null"))
            }
        }
        #endif
        guard !items.isEmpty else { return }
        await player.restore(items: items, at: snapshot.index, offset: snapshot.offset)
        queueRevision += 1
    }

    func next() {
        Task { await player.next() }
    }

    func previous() {
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
            guard !track.unavailable,
                let root = roots[track.sourceId], let relative = track.relativePath
            else {
                return nil
            }
            return PlaybackItem(track: track, url: root.appendingPathComponent(relative))
        }
    }

    // MARK: - Playlists

    func createPlaylist() {
        do {
            pendingPlaylistId = try playlistRepo.create(name: "New Playlist").id
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
                case .local: try? await rescan(source: source)
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
        let sync = SubsonicSync(client: client, sourceId: source.id, db: db)
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
            Log.library.error("subsonic sync failed: \(error, privacy: .public)")
        }
        scanProgress = nil
    }

    private func rescan(source: Source) async throws {
        for try await progress in scanner.scanStream(source: source) {
            scanProgress = progress
        }
        scanProgress = nil
    }
}
