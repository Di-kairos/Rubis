import EscapementCore
import Foundation
import GRDB
import Testing

@testable import MusicLibrary

/// Живой баг S23: у 174 из 288 артистов владельца справа пусто.
struct ArtistAlbumsTests {
    private func track(_ source: Source, _ path: String, artist: Int64?, album: Int64?) -> Track {
        Track(
            sourceId: source.id, relativePath: path, title: path, artistId: artist,
            albumId: album, duration: 1, codec: "flac", sampleRate: 44_100)
    }

    @Test func artistShowsCompilationsTheyPlayOn() throws {
        let db = try AppDatabase.inMemory()
        let source = Source(kind: .local, displayName: "L")
        try SourceRepository(db: db).upsert(source)
        let artists = ArtistRepository(db: db)
        let various = try artists.findOrCreate(name: "Various Artists")
        let guest = try artists.findOrCreate(name: "Little Dragon")
        let albums = AlbumRepository(db: db)
        let mix = try albums.insert(Album(title: "DJ-Kicks", sortTitle: "dj-kicks", artistId: various.id))
        let own = try albums.insert(Album(title: "Ritual Union", sortTitle: "ritual union", artistId: guest.id))
        _ = try TrackRepository(db: db).insert([
            track(source, "1.flac", artist: guest.id, album: mix.id),
            track(source, "2.flac", artist: various.id, album: mix.id),
            track(source, "3.flac", artist: guest.id, album: own.id),
        ])

        let shown = try albums.albums(byArtist: try #require(guest.id)).map(\.title)
        #expect(Set(shown) == ["DJ-Kicks", "Ritual Union"])
        #expect(try albums.albums(byArtist: try #require(various.id)).map(\.title) == ["DJ-Kicks"])
    }

    @Test func tidyMergesSortTagTwinsAndDropsOrphans() throws {
        let db = try AppDatabase.inMemory()
        let source = Source(kind: .local, displayName: "L")
        try SourceRepository(db: db).upsert(source)
        // Двойник, как его создавал прежний ключ по сырому ARTISTSORT.
        let (raw, normal, orphan) = try db.writer.write { database in
            var raw = Artist(name: "Kamasi Washington", sortName: "Kamasi Washington")
            try raw.insert(database)
            var normal = Artist(name: "Kamasi Washington", sortName: "kamasi washington")
            try normal.insert(database)
            var orphan = Artist(name: "Tjomur • Jan Steiner", sortName: "tjomur • jan steiner")
            try orphan.insert(database)
            return (raw, normal, orphan)
        }
        let album = try AlbumRepository(db: db).insert(
            Album(title: "Heaven and Earth", sortTitle: "heaven and earth", artistId: normal.id))
        _ = try TrackRepository(db: db).insert([
            track(source, "1.flac", artist: raw.id, album: album.id)
        ])

        try db.writer.write { try ArtistTidy.run($0) }

        let left = try ArtistRepository(db: db).all()
        #expect(left.map(\.name) == ["Kamasi Washington"])
        let survivor = try #require(left.first?.id)
        #expect(left.first?.sortName == "kamasi washington")
        #expect(try AlbumRepository(db: db).albums(byArtist: survivor).map(\.title) == ["Heaven and Earth"])
        #expect(try TrackRepository(db: db).tracks(byArtist: survivor).count == 1)
        #expect(orphan.id != survivor)
    }
}
