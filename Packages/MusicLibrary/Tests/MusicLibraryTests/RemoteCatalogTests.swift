import EscapementCore
import Foundation
import Testing

@testable import MusicLibrary

/// Опоры синхронизации серверного каталога (фаза 6, pack 3): по этим двум
/// методам синк узнаёт свои строки и не плодит дубли альбомов.
struct RemoteCatalogTests {

    private func makeServerSource(_ db: TestDatabase) throws -> Source {
        let source = Source(
            kind: .subsonic, displayName: "Navidrome",
            serverUrl: "https://music.example.org")
        try SourceRepository(db: db).upsert(source)
        return source
    }

    private func remoteTrack(_ id: String, source: Source) -> Track {
        Track(
            sourceId: source.id, remoteId: id, title: "Song \(id)", duration: 100,
            codec: "flac", sampleRate: 44100)
    }

    @Test func remoteIdsMapBackToRows() throws {
        let db = try AppDatabase.inMemory()
        let source = try makeServerSource(db)
        let repo = TrackRepository(db: db)
        let inserted = try repo.insert([remoteTrack("so-1", source: source)])

        let map = try repo.remoteIds(inSource: source.id)
        #expect(map.count == 1)
        #expect(map["so-1"] == inserted.first?.id)
    }

    @Test func localTracksStayOutOfTheRemoteMap() throws {
        // У локальных строк `remote_id` пуст — синк не должен считать их своими
        // и уж тем более удалять, когда сервер о них не знает.
        let db = try AppDatabase.inMemory()
        let server = try makeServerSource(db)
        let local = Source(kind: .local, displayName: "Folder")
        try SourceRepository(db: db).upsert(local)

        let repo = TrackRepository(db: db)
        _ = try repo.insert([
            remoteTrack("so-1", source: server),
            Track(
                sourceId: local.id, relativePath: "a.flac", title: "Local", duration: 10,
                codec: "flac", sampleRate: 44100),
        ])

        #expect(try repo.remoteIds(inSource: server.id).keys.sorted() == ["so-1"])
        #expect(try repo.remoteIds(inSource: local.id).isEmpty)
    }

    @Test func albumIsCreatedOnceAndFoundAgain() throws {
        let db = try AppDatabase.inMemory()
        let repo = AlbumRepository(db: db)
        let artist = try ArtistRepository(db: db).findOrCreate(name: "Keith Jarrett")

        let first = try repo.findOrCreate(
            title: "The Köln Concert", artistId: artist.id, albumArtist: "Keith Jarrett",
            year: 1975)
        let second = try repo.findOrCreate(
            title: "The Köln Concert", artistId: artist.id, albumArtist: "Keith Jarrett",
            year: 1975)

        #expect(first.id == second.id)
        #expect(try repo.all().count == 1)
        #expect(first.sortTitle == "koln concert")
    }

    @Test func sameTitleFromAnotherArtistIsAnotherAlbum() throws {
        let db = try AppDatabase.inMemory()
        let repo = AlbumRepository(db: db)
        let artists = ArtistRepository(db: db)
        let one = try artists.findOrCreate(name: "Bill Evans")
        let other = try artists.findOrCreate(name: "Chet Baker")

        let first = try repo.findOrCreate(
            title: "Alone", artistId: one.id, albumArtist: "Bill Evans", year: 1968)
        let second = try repo.findOrCreate(
            title: "Alone", artistId: other.id, albumArtist: "Chet Baker", year: 1974)

        #expect(first.id != second.id)
        #expect(try repo.all().count == 2)
    }
}
