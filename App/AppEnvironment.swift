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
        // секунду, чтобы ⌘Q в любой момент терял не больше секунды.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.saveTrackProgress()
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
        Task { await player.play(items: items, startAt: start) }
    }

    /// Треки сразу после текущего.
    func playNext(tracks: [Track]) {
        let items = resolveItems(tracks: tracks)
        Task { await player.playNext(items: items) }
    }

    /// Треки в конец очереди.
    func addToQueue(tracks: [Track]) {
        let items = resolveItems(tracks: tracks)
        Task { await player.enqueue(items: items) }
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
        Task { await player.setShuffleMode(next) }
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
    private func saveTrackProgress() async {
        switch playbackState {
        case .playing, .paused:
            guard let time = await player.playbackTime() else { return }
            PlaybackSnapshot.saveProgress(
                index: await player.currentIndex(), offset: time.current, to: .standard)
        default:
            return
        }
    }

    /// Восстановление очереди при запуске: состав, индекс и позиция — без звука.
    /// Первый Play продолжит трек с той же секунды.
    private func restoreQueue() async {
        guard let snapshot = PlaybackSnapshot.load(from: .standard),
            let tracks = try? trackRepo.tracks(ids: snapshot.trackIds)
        else { return }
        let items = resolveItems(tracks: tracks)
        guard !items.isEmpty else { return }
        await player.restore(items: items, at: snapshot.index, offset: snapshot.offset)
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

    func rescanAll() {
        Task {
            guard let sources = try? sourceRepo.all() else { return }
            for source in sources where source.kind == .local && source.enabled {
                try? await rescan(source: source)
            }
        }
    }

    private func rescan(source: Source) async throws {
        for try await progress in scanner.scanStream(source: source) {
            scanProgress = progress
        }
        scanProgress = nil
    }
}
