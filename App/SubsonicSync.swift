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

    init(client: SubsonicClient, sourceId: String, db: AppDatabase) {
        self.client = client
        self.sourceId = sourceId
        self.db = db
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
                    continuation.yield(summary)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func sync(report: (Progress) -> Void) async throws -> Progress {
        let albums = try await allAlbums()
        let trackRepo = TrackRepository(db: db)
        let albumRepo = AlbumRepository(db: db)
        let artistRepo = ArtistRepository(db: db)

        let known = try trackRepo.remoteIds(inSource: sourceId)
        var seen: Set<String> = []
        var inserted = 0

        for (index, remoteAlbum) in albums.enumerated() {
            report(.albums(done: index, total: albums.count))
            let detail = try await client.album(id: remoteAlbum.id)

            let artist = try remoteAlbum.artist.map { try artistRepo.findOrCreate(name: $0) }
            let album = try albumRepo.findOrCreate(
                title: SubsonicCatalog.album(from: remoteAlbum, artistId: artist?.id).title,
                artistId: artist?.id, albumArtist: remoteAlbum.artist, year: remoteAlbum.year)

            var fresh: [Track] = []
            for song in detail.songs {
                seen.insert(song.id)
                // Уже лежащие треки не переписываем: у сервера нет отметки
                // времени, по которой можно понять, что запись изменилась.
                // ponytail: расхождение чинится удалением источника и новой
                // синхронизацией — вернуться сюда, если начнёт мешать.
                guard known[song.id] == nil else { continue }
                let songArtist = try song.artist.map { try artistRepo.findOrCreate(name: $0) }
                fresh.append(
                    SubsonicCatalog.track(
                        from: song, sourceId: sourceId,
                        artistId: songArtist?.id ?? artist?.id, albumId: album.id))
            }
            if !fresh.isEmpty {
                _ = try trackRepo.insert(fresh)
                inserted += fresh.count
            }
        }

        // Пропавшее у сервера уходит и отсюда — но только когда сервер вообще
        // что-то отдал: пустой ответ бывает и у сломанного сервера, а стирать
        // библиотеку из-за сетевой икоты нельзя.
        var removed = 0
        if !albums.isEmpty {
            let gone = known.filter { !seen.contains($0.key) }.map(\.value)
            if !gone.isEmpty {
                try trackRepo.delete(ids: gone)
                removed = gone.count
            }
        }
        return .finished(tracks: inserted, removed: removed)
    }

    /// `getAlbumList2` отдаёт каталог страницами по 500.
    private func allAlbums() async throws -> [SubsonicAlbum] {
        var result: [SubsonicAlbum] = []
        var offset = 0
        let page = 500
        while true {
            let batch = try await client.albums(offset: offset, size: page)
            result.append(contentsOf: batch)
            if batch.count < page { break }
            offset += page
        }
        return result
    }
}
