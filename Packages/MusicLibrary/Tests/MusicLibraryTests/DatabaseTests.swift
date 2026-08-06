import EscapementCore
import Foundation
import Testing

@testable import MusicLibrary

struct MigrationTests {
    @Test func migratesFromScratch() throws {
        let db = try AppDatabase.inMemory()
        let tables = try db.reader.read { database in
            try String.fetchAll(
                database,
                sql:
                    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'"
            )
        }
        for expected in [
            "source", "artist", "album", "track", "playlist", "playlist_item", "play_history",
        ] {
            #expect(tables.contains(expected), "missing table \(expected)")
        }
        let ftsExists = try db.reader.read { database in
            try Bool.fetchOne(
                database,
                sql: "SELECT count(*) > 0 FROM sqlite_master WHERE name = 'track_fts'")!
        }
        #expect(ftsExists)
    }
}

struct CRUDTests {
    private func makeSource(_ db: TestDatabase) throws -> Source {
        let source = Source(kind: .local, displayName: "Test Library")
        try SourceRepository(db: db).upsert(source)
        return source
    }

    @Test func insertAndFetchTrack() throws {
        let db = try AppDatabase.inMemory()
        let source = try makeSource(db)
        let artist = try ArtistRepository(db: db).findOrCreate(name: "Miles Davis")
        let album = try AlbumRepository(db: db).insert(
            Album(title: "Kind of Blue", sortTitle: "kind of blue", artistId: artist.id))

        let repo = TrackRepository(db: db)
        let inserted = try repo.insert([
            Track(
                sourceId: source.id, relativePath: "kob/01.flac", title: "So What",
                artistId: artist.id, albumId: album.id, trackNo: 1, duration: 545.0,
                codec: "flac", sampleRate: 192_000, bitDepth: 24)
        ])
        #expect(inserted[0].id != nil)

        let fetched = try repo.tracks(inAlbum: album.id!)
        #expect(fetched.count == 1)
        #expect(fetched[0].title == "So What")
        #expect(fetched[0].sampleRate == 192_000)
    }

    @Test func artistDedupBySortName() throws {
        let db = try AppDatabase.inMemory()
        let repo = ArtistRepository(db: db)
        let a = try repo.findOrCreate(name: "The Beatles")
        let b = try repo.findOrCreate(name: "Beatles")
        #expect(a.id == b.id, "sort-name normalization must dedup 'The Beatles' / 'Beatles'")
    }

    @Test func playlistRoundTrip() throws {
        let db = try AppDatabase.inMemory()
        let source = try makeSource(db)
        let tracks = try TrackRepository(db: db).insert(
            (1...3).map {
                Track(
                    sourceId: source.id, relativePath: "t\($0).flac", title: "Track \($0)",
                    duration: 100, codec: "flac", sampleRate: 44_100)
            })
        let repo = PlaylistRepository(db: db)
        let playlist = try repo.create(name: "Mix")
        let ids = tracks.compactMap(\.id)
        try repo.setTracks(ids.reversed(), in: playlist.id!)
        #expect(try repo.trackIds(in: playlist.id!) == ids.reversed())

        try repo.setTracks(ids, in: playlist.id!)
        #expect(try repo.trackIds(in: playlist.id!) == ids)
    }

    @Test func playlistAppendSkipsDuplicatesAndKeepsOrder() throws {
        let db = try AppDatabase.inMemory()
        let source = try makeSource(db)
        let trackRepo = TrackRepository(db: db)
        let tracks = try trackRepo.insert(
            (1...3).map {
                Track(
                    sourceId: source.id, relativePath: "t\($0).flac", title: "Track \($0)",
                    duration: 100, codec: "flac", sampleRate: 44_100)
            })
        let ids = tracks.compactMap(\.id)
        let repo = PlaylistRepository(db: db)
        let playlist = try repo.create(name: "Mix")

        try repo.append([ids[2], ids[0]], to: playlist.id!)
        try repo.append([ids[0], ids[1]], to: playlist.id!)
        let stored = try repo.trackIds(in: playlist.id!)
        #expect(stored == [ids[2], ids[0], ids[1]])
        // Порядок плейлиста, а не порядок id в таблице.
        #expect(
            try trackRepo.tracks(ids: stored).map(\.title) == ["Track 3", "Track 1", "Track 2"])

        try repo.rename(id: playlist.id!, to: "Evening")
        #expect(try repo.all().first?.name == "Evening")
    }

    @Test func cascadeDeleteSourceRemovesTracks() throws {
        let db = try AppDatabase.inMemory()
        let source = try makeSource(db)
        let trackRepo = TrackRepository(db: db)
        _ = try trackRepo.insert([
            Track(
                sourceId: source.id, relativePath: "x.flac", title: "X",
                duration: 1, codec: "flac", sampleRate: 44_100)
        ])
        try SourceRepository(db: db).delete(id: source.id)
        #expect(try trackRepo.count() == 0)
    }
}

struct NormalizeTests {
    @Test func sortNameRules() {
        #expect(Normalize.sortName(for: "The Beatles") == "beatles")
        #expect(Normalize.sortName(for: "A Tribe Called Quest") == "tribe called quest")
        #expect(Normalize.sortName(for: "Björk") == "bjork")
        #expect(Normalize.sortName(for: "Кино") == "кино")
        #expect(Normalize.sortName(for: "  Miles Davis  ") == "miles davis")
    }
}

struct FTSTests {
    private func seed(_ db: TestDatabase) throws {
        let source = Source(kind: .local, displayName: "L")
        try SourceRepository(db: db).upsert(source)
        let bjork = try ArtistRepository(db: db).findOrCreate(name: "Björk")
        let kino = try ArtistRepository(db: db).findOrCreate(name: "Кино")
        _ = try TrackRepository(db: db).insert([
            Track(
                sourceId: source.id, relativePath: "1.flac", title: "Jóga",
                artistId: bjork.id, duration: 1, codec: "flac", sampleRate: 44_100),
            Track(
                sourceId: source.id, relativePath: "2.flac", title: "Группа крови",
                artistId: kino.id, duration: 1, codec: "flac", sampleRate: 44_100),
        ])
    }

    @Test func searchIgnoresDiacritics() throws {
        let db = try AppDatabase.inMemory()
        try seed(db)
        let repo = TrackRepository(db: db)
        #expect(try repo.search("joga").count == 1)
        #expect(try repo.search("bjork").count == 1)
    }

    @Test func searchCyrillicPrefix() throws {
        let db = try AppDatabase.inMemory()
        try seed(db)
        let repo = TrackRepository(db: db)
        let hits = try repo.search("групп")
        #expect(hits.count == 1)
        #expect(hits[0].track.title == "Группа крови")
        #expect(hits[0].artistName == "Кино")
    }

    @Test func updateKeepsIndexInSync() throws {
        let db = try AppDatabase.inMemory()
        try seed(db)
        let repo = TrackRepository(db: db)
        var track = try repo.search("Jóga")[0].track
        track.title = "Hyperballad"
        try db.writer.write { try track.update($0) }
        #expect(try repo.search("joga").isEmpty)
        #expect(try repo.search("hyperballad").count == 1)
    }

    @Test func quotesInQueryDoNotBreakMatch() throws {
        let db = try AppDatabase.inMemory()
        try seed(db)
        #expect(try TrackRepository(db: db).search("\"jo\"ga\"").count == 1)
    }
}

struct ObservationTests {
    @Test func albumObservationEmitsOnChange() async throws {
        let db = try AppDatabase.inMemory()
        var iterator = LibraryObservation.albums(db: db).makeAsyncIterator()

        let initial = try await iterator.next()
        #expect(initial == [])

        _ = try AlbumRepository(db: db).insert(Album(title: "Low", sortTitle: "low"))
        let updated = try await iterator.next()
        #expect(updated?.count == 1)
        #expect(updated?[0].title == "Low")
    }
}
