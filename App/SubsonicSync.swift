import EscapementCore
import Foundation
import MusicLibrary
import SubsonicKit

/// Синхронизация каталога сервера в те же таблицы, что и локальная музыка
/// (фаза 6, pack 3). Живёт в приложении: сеть знает `SubsonicKit`, БД —
/// `MusicLibrary`, а встречаются они только здесь (SPEC §3.1).
///
/// Сервер — источник правды: чего у него нет, того нет и в библиотеке.
actor SubsonicSync {
    private let client: SubsonicClient
    private let sourceId: String
    private let db: AppDatabase
    private let covers: CoverCache
    private let ledger: NetworkLedger
    /// Сколько запросов ушло за обход: каталог страницами, альбом за
    /// альбомом, обложки. В журнал соединений — одной строкой с числом,
    /// а не сотнями записей, вытесняющих всё остальное из окна в 1000.
    private var requests = 0

    init(
        client: SubsonicClient, sourceId: String, db: AppDatabase, covers: CoverCache,
        ledger: NetworkLedger
    ) {
        self.client = client
        self.sourceId = sourceId
        self.db = db
        self.covers = covers
        self.ledger = ledger
    }

    /// Ход синхронизации — для полоски в сайдбаре, как у скана папок.
    enum Progress: Sendable, Equatable {
        case albums(done: Int, total: Int)
        case finished(tracks: Int, removed: Int)
    }

    /// Обходит каталог постранично и складывает его в библиотеку.
    /// Возвращает поток шагов: экран показывает прогресс, не дожидаясь конца.
    func run() -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let summary = try await self.sync { progress in
                        continuation.yield(progress)
                    }
                    await self.account(succeeded: true)
                    continuation.yield(summary)
                    continuation.finish()
                } catch {
                    await self.account(succeeded: false)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Одна строка журнала на весь обход. Размер ответов клиент не считает —
    /// в журнале честный ноль, а не выдуманное число.
    private func account(succeeded: Bool) async {
        await ledger.record(
            host: client.host, purpose: "Catalog sync · \(requests) requests",
            succeeded: succeeded, bytes: 0)
    }

    private func sync(report: (Progress) -> Void) async throws -> Progress {
        let albums = try await allAlbums()
        let trackRepo = TrackRepository(db: db)
        let albumRepo = AlbumRepository(db: db)
        let artistRepo = ArtistRepository(db: db)

        let known = try trackRepo.remoteIds(inSource: sourceId)
        var seen: Set<String> = []
        /// Известные треки, которые сервер отдал снова: снять пометку
        /// недоступности, если прошлый обход их не досчитался.
        var reappeared: [Int64] = []
        var inserted = 0

        for (index, remoteAlbum) in albums.enumerated() {
            report(.albums(done: index, total: albums.count))
            let detail = try await client.album(id: remoteAlbum.id)
            requests += 1

            let artist = try remoteAlbum.artist.map { try artistRepo.findOrCreate(name: $0) }
            let album = try albumRepo.findOrCreate(
                title: SubsonicCatalog.album(from: remoteAlbum, artistId: artist?.id).title,
                artistId: artist?.id, albumArtist: remoteAlbum.artist, year: remoteAlbum.year)

            await fetchCover(for: remoteAlbum, album: album, repo: albumRepo)

            var fresh: [Track] = []
            // Известные треки альбома — одной выборкой: изменившиеся теги
            // (название, формат, длительность, номер) переписываются под тем
            // же id, чтобы плейлисты и история пережили правку на сервере.
            let knownIDs = detail.songs.compactMap { known[$0.id] }
            let stored = Dictionary(
                uniqueKeysWithValues: try trackRepo.tracks(ids: knownIDs).compactMap { row in
                    row.id.map { ($0, row) }
                })
            for song in detail.songs {
                seen.insert(song.id)
                let songArtist = try song.artist.map { try artistRepo.findOrCreate(name: $0) }
                var candidate = SubsonicCatalog.track(
                    from: song, sourceId: sourceId,
                    artistId: songArtist?.id ?? artist?.id, albumId: album.id)
                guard let knownID = known[song.id] else {
                    fresh.append(candidate)
                    continue
                }
                reappeared.append(knownID)
                guard let current = stored[knownID] else { continue }
                candidate.id = knownID
                candidate.addedAt = current.addedAt
                candidate.unavailable = current.unavailable
                if Self.differs(current, candidate) { try trackRepo.update(candidate) }
            }
            if !fresh.isEmpty {
                _ = try trackRepo.insert(fresh)
                inserted += fresh.count
            }
        }

        // Пропавшее у сервера гаснет, а не удаляется: удаление каскадом
        // вычищало бы плейлисты, а неполный обход (сервер отдал часть
        // каталога) — необратимо. Погашенное вернётся следующим обходом,
        // который его снова увидит. Пустой ответ — вовсе не повод трогать
        // библиотеку: так выглядит и сломанный сервер.
        try trackRepo.setUnavailable(false, ids: reappeared)
        var removed = 0
        if !albums.isEmpty {
            let gone = known.filter { !seen.contains($0.key) }.map(\.value)
            removed = try trackRepo.setUnavailable(true, ids: gone)
        }
        return .finished(tracks: inserted, removed: removed)
    }

    /// Поля, которые сервер может изменить у известного трека.
    private static func differs(_ a: Track, _ b: Track) -> Bool {
        a.title != b.title || a.artistId != b.artistId || a.albumId != b.albumId
            || a.trackNo != b.trackNo || a.discNo != b.discNo || a.duration != b.duration
            || a.codec != b.codec || a.sampleRate != b.sampleRate || a.bitDepth != b.bitDepth
            || a.channels != b.channels || a.bitrate != b.bitrate
    }

    /// Обложка с сервера в общий кэш (фаза 6, pack 4). Серверная картинка
    /// ложится туда же, куда кладёт свою сканер папок, и опознаётся тем же
    /// `cover_hash` — экраны о происхождении обложки ничего не знают.
    ///
    /// Уже одетый альбом не трогаем: лишний запрос на каждую синхронизацию
    /// платится сетью, а картинка от этого не меняется. Сбой не роняет синк —
    /// обложка приедет при следующем заходе.
    private func fetchCover(
        for remote: SubsonicAlbum, album: Album, repo: AlbumRepository
    ) async {
        guard let albumId = album.id, album.coverHash == nil,
            let coverArtId = remote.coverArt
        else { return }
        do {
            requests += 1
            let data = try await client.coverArt(id: coverArtId)
            let hash = try covers.store(data)
            try repo.setCoverHashIfMissing(hash, albumId: albumId)
        } catch {
            Log.library.debug("subsonic cover skipped: \(Log.describe(error), privacy: .public)")
        }
    }

    /// `getAlbumList2` отдаёт каталог страницами по 500.
    private func allAlbums() async throws -> [SubsonicAlbum] {
        var result: [SubsonicAlbum] = []
        var offset = 0
        let page = 500
        while true {
            requests += 1
            let batch = try await client.albums(offset: offset, size: page)
            result.append(contentsOf: batch)
            if batch.count < page { break }
            offset += page
        }
        return result
    }
}
