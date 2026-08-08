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

    @Test func allWithNamesJoinsArtistAndAlbum() throws {
        let db = try AppDatabase.inMemory()
        try seed(db)
        let rows = try TrackRepository(db: db).allWithNames()
        #expect(rows.count == 2)
        let joga = rows.first { $0.track.title == "Jóga" }
        #expect(joga?.artistName == "Björk")
        #expect(joga?.albumTitle == nil)
        #expect(rows.first { $0.track.title == "Группа крови" }?.artistName == "Кино")
    }
}

struct GroupedSearchTests {
    private func seed(_ db: TestDatabase) throws -> (Artist, Album) {
        let source = Source(kind: .local, displayName: "L")
        try SourceRepository(db: db).upsert(source)
        let beatles = try ArtistRepository(db: db).findOrCreate(name: "The Beatles")
        _ = try ArtistRepository(db: db).findOrCreate(name: "Björk")
        let album = try AlbumRepository(db: db).insert(
            Album(
                title: "Abbey Road", sortTitle: Normalize.sortName(for: "Abbey Road"),
                artistId: beatles.id))
        _ = try TrackRepository(db: db).insert([
            Track(
                sourceId: source.id, relativePath: "1.flac", title: "Come Together",
                artistId: beatles.id, albumId: album.id, trackNo: 1, duration: 1,
                codec: "flac", sampleRate: 44_100),
            Track(
                sourceId: source.id, relativePath: "2.flac", title: "Something",
                artistId: beatles.id, albumId: album.id, trackNo: 2, duration: 1,
                codec: "flac", sampleRate: 44_100),
        ])
        return (beatles, album)
    }

    @Test func artistSearchIgnoresArticleAndDiacritics() throws {
        let db = try AppDatabase.inMemory()
        _ = try seed(db)
        let repo = ArtistRepository(db: db)
        #expect(try repo.search("beat").map(\.name) == ["The Beatles"])
        #expect(try repo.search("The Beat").map(\.name) == ["The Beatles"])
        #expect(try repo.search("bjork").map(\.name) == ["Björk"])
        #expect(try repo.search("  ").isEmpty, "пустой запрос не тянет всю таблицу")
    }

    @Test func albumSearchMatchesPrefix() throws {
        let db = try AppDatabase.inMemory()
        _ = try seed(db)
        #expect(try AlbumRepository(db: db).search("abbey").map(\.title) == ["Abbey Road"])
        #expect(try AlbumRepository(db: db).search("road").isEmpty, "поиск префиксный")
    }

    @Test func wildcardsInQueryAreEscaped() throws {
        let db = try AppDatabase.inMemory()
        _ = try seed(db)
        // «%» как шаблон вернул бы всех; экранированный — никого.
        #expect(try ArtistRepository(db: db).search("%").isEmpty)
        #expect(try ArtistRepository(db: db).search("_eatles").isEmpty)
    }

    @Test func artistTracksComeInAlbumOrder() throws {
        let db = try AppDatabase.inMemory()
        let (beatles, _) = try seed(db)
        let tracks = try TrackRepository(db: db).tracks(byArtist: beatles.id!)
        #expect(tracks.map(\.title) == ["Come Together", "Something"])
    }
}

struct TrackSortTests {
    private func hit(
        _ title: String, _ artist: String?, _ album: String?, _ duration: Double,
        _ codec: String
    ) -> SearchHit {
        SearchHit(
            track: Track(
                id: Int64(title.count), sourceId: "s", title: title, duration: duration,
                codec: codec, sampleRate: 44_100),
            artistName: artist, albumTitle: album)
    }

    private var rows: [SearchHit] {
        [
            hit("Track 10", "Björk", "Post", 120, "alac"),
            hit("track 2", "bjork jr", nil, 300, "flac"),
            hit("Ábc", nil, "Debut", 60, "dsf"),
        ]
    }

    @Test func titleSortIsHumanAndCaseInsensitive() {
        let asc = TrackSort.sorted(rows, by: .title, ascending: true).map(\.track.title)
        #expect(asc == ["Ábc", "track 2", "Track 10"])
    }

    @Test func descendingReversesOrder() {
        let desc = TrackSort.sorted(rows, by: .duration, ascending: false).map(\.track.duration)
        #expect(desc == [300, 120, 60])
    }

    @Test func missingNamesSortFirst() {
        let byArtist = TrackSort.sorted(rows, by: .artist, ascending: true).map { $0.artistName }
        #expect(byArtist == [nil, "Björk", "bjork jr"])
        let byAlbum = TrackSort.sorted(rows, by: .album, ascending: true).map { $0.albumTitle }
        #expect(byAlbum == [nil, "Debut", "Post"])
    }

    @Test func equalKeysKeepIdOrderInBothDirections() {
        let same = [
            hit("B", "same", nil, 100, "flac"),
            hit("AA", "same", nil, 100, "flac"),
        ]
        // id = длина названия: 1 («B») и 2 («AA»).
        let asc = TrackSort.sorted(same, by: .artist, ascending: true).map(\.id)
        let desc = TrackSort.sorted(same, by: .artist, ascending: false).map(\.id)
        #expect(asc == [1, 2])
        #expect(desc == asc, "равные ключи не должны переворачиваться вместе с направлением")
    }

    @Test func formatSortsByCodec() {
        let byFormat = TrackSort.sorted(rows, by: .format, ascending: true).map(\.track.codec)
        #expect(byFormat == ["alac", "dsf", "flac"])
    }
}

struct ObservationTests {
    private func makeSource(_ db: TestDatabase) throws -> Source {
        let source = Source(kind: .local, displayName: "Test Library")
        try SourceRepository(db: db).upsert(source)
        return source
    }

    @Test func albumObservationEmitsOnChange() async throws {
        let db = try AppDatabase.inMemory()
        var iterator = LibraryObservation.albums(db: db).makeAsyncIterator()

        let initial = try await iterator.next()
        #expect(initial == [])

        // Альбом без треков наблюдение прячет (пустая строка после скана
        // не должна показываться анонимной плиткой) — вставка альбома даёт
        // промежуточную эмиссию [], поэтому ждём первую непустую.
        let source = try makeSource(db)
        let album = try AlbumRepository(db: db).insert(Album(title: "Low", sortTitle: "low"))
        _ = try TrackRepository(db: db).insert([
            Track(
                sourceId: source.id, relativePath: "low/01.flac", title: "Speed of Life",
                albumId: album.id, trackNo: 1, duration: 166.0,
                codec: "flac", sampleRate: 44_100, bitDepth: 16)
        ])
        var updated: [Album] = []
        while let emission = try await iterator.next() {
            if !emission.isEmpty {
                updated = emission
                break
            }
        }
        #expect(updated.count == 1)
        #expect(updated.first?.title == "Low")
    }

    @Test func albumObservationHidesTracklessAlbums() async throws {
        let db = try AppDatabase.inMemory()
        var iterator = LibraryObservation.albums(db: db).makeAsyncIterator()
        _ = try await iterator.next()

        _ = try AlbumRepository(db: db).insert(Album(title: "Empty", sortTitle: "empty"))
        let emitted = try await iterator.next()
        #expect(emitted == [])
    }

    @Test func albumObservationFiltersBySource() async throws {
        let db = try AppDatabase.inMemory()
        let sourceRepo = SourceRepository(db: db)
        let ambient = Source(kind: .local, displayName: "Ambient")
        let jazz = Source(kind: .local, displayName: "Jazz")
        try sourceRepo.upsert(ambient)
        try sourceRepo.upsert(jazz)

        let albums = AlbumRepository(db: db)
        let trackRepo = TrackRepository(db: db)
        let discreet = try albums.insert(Album(title: "Discreet Music", sortTitle: "discreet"))
        let blue = try albums.insert(Album(title: "Kind of Blue", sortTitle: "kind of blue"))
        _ = try trackRepo.insert([
            Track(
                sourceId: ambient.id, relativePath: "eno/01.flac", title: "Discreet Music",
                albumId: discreet.id, trackNo: 1, duration: 1800.0,
                codec: "flac", sampleRate: 44_100, bitDepth: 16),
            Track(
                sourceId: jazz.id, relativePath: "davis/01.flac", title: "So What",
                albumId: blue.id, trackNo: 1, duration: 545.0,
                codec: "flac", sampleRate: 44_100, bitDepth: 16),
        ])

        var iterator = LibraryObservation.albums(db: db, sourceId: ambient.id)
            .makeAsyncIterator()
        let filtered = try await iterator.next()
        #expect(filtered?.map(\.title) == ["Discreet Music"])
    }
}
