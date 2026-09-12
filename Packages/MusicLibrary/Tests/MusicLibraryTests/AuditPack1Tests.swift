import EscapementCore
import Foundation
import GRDB
import Testing

@testable import MusicLibrary

/// Дополнение к `AuditRegressionTests` (аудит 2026-09-12, pack 1): переходы
/// «файл ↔ сегменты» сохраняют ссылки плейлистов, дедупликация не сливает
/// разные файлы, парсер CUE держит границы полей.
struct AuditPack1Tests {
    private func rig() throws -> (URL, TestDatabase, LibraryScanner, Source) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-pack1-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = try #require(
            try FileManager.default.contentsOfDirectory(
                at: ScannerTests.fixturesDir, includingPropertiesForKeys: nil
            ).first { $0.pathExtension == "flac" })
        try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("disc.flac"))
        let db = try AppDatabase.inMemory()
        var source = Source(kind: .local, displayName: "Audit")
        source.bookmark = try LibraryScanner.makeBookmark(for: root)
        try SourceRepository(db: db).upsert(source)
        let scanner = LibraryScanner(
            db: db, covers: try CoverCache(root: root.appendingPathComponent("covers")),
            logURL: root.appendingPathComponent("scan.log"))
        return (root, db, scanner, source)
    }

    private func sheet() -> String {
        """
        TITLE "Audit Album"
        FILE "disc.flac" WAVE
          TRACK 01 AUDIO
            TITLE "First"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Second"
            INDEX 01 00:02:00
        """
    }

    // MARK: - Парсер

    @Test func timeFieldsStayInsideTheirRanges() {
        #expect(CueSheet.time("00:60:00") == nil)
        #expect(CueSheet.time("00:00:75") == nil)
        #expect(CueSheet.time("-1:00:00") == nil)
        #expect(CueSheet.time("1.5:00:00") == nil)
        #expect(CueSheet.time("nan:00:00") == nil)
        #expect(CueSheet.time("99999999999999999999:00:00") == nil)
        #expect(CueSheet.time("100:00:00") == 6000)
        #expect(CueSheet.time("01:02:03") == 62 + 3.0 / 75)
    }

    @Test func tracksOutOfOrderAreDropped() throws {
        let parsed = try #require(
            CueSheet.parse(
                """
                FILE "disc.flac" WAVE
                  TRACK 01 AUDIO
                    INDEX 01 00:01:00
                  TRACK 02 AUDIO
                    INDEX 01 00:00:37
                  TRACK 03 AUDIO
                    INDEX 01 00:01:00
                  TRACK 04 AUDIO
                    INDEX 01 00:05:00
                """))
        #expect(parsed.tracks.map(\.number) == [1, 4])
        #expect(parsed.tracks.first?.end == 5)
    }

    // MARK: - Переходы «файл ↔ сегменты»

    @Test func sheetArrivalKeepsWholeFileIdentityAndPlaylist() async throws {
        let (root, db, scanner, source) = try rig()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await scanner.scan(source: source)
        let whole = try #require(try await db.reader.read { try Track.fetchOne($0) })
        let wholeID = try #require(whole.id)
        let playlists = PlaylistRepository(db: db)
        let playlistID = try #require(playlists.create(name: "Keep").id)
        try playlists.setTracks([wholeID], in: playlistID)

        try sheet().write(
            to: root.appendingPathComponent("disc.cue"), atomically: true, encoding: .utf8)
        _ = try await scanner.scan(source: source)

        let rows = try await db.reader.read { try Track.order(Column("cue_start")).fetchAll($0) }
        #expect(rows.count == 2)
        #expect(rows.first?.id == wholeID)
        #expect(rows.first?.cueStart == 0)
        #expect(try playlists.trackIds(in: playlistID) == [wholeID])
    }

    @Test func sheetRemovalMovesPlaylistEntriesToTheWholeFile() async throws {
        let (root, db, scanner, source) = try rig()
        defer { try? FileManager.default.removeItem(at: root) }
        let cue = root.appendingPathComponent("disc.cue")
        try sheet().write(to: cue, atomically: true, encoding: .utf8)
        _ = try await scanner.scan(source: source)
        let segments = try await db.reader.read {
            try Track.order(Column("cue_start")).fetchAll($0)
        }
        let second = try #require(segments.last?.id)
        let playlists = PlaylistRepository(db: db)
        let playlistID = try #require(playlists.create(name: "Keep").id)
        try playlists.setTracks([second], in: playlistID)

        try FileManager.default.removeItem(at: cue)
        _ = try await scanner.scan(source: source)

        let rows = try await db.reader.read { try Track.fetchAll($0) }
        #expect(rows.count == 1)
        #expect(rows.first?.cueStart == nil)
        // Первый сегмент стал целым файлом и сохранил id; ссылка со второго
        // переехала на него, а не пропала.
        #expect(rows.first?.id == segments.first?.id)
        #expect(try playlists.trackIds(in: playlistID) == [rows.first?.id].compactMap { $0 })
        _ = try await scanner.scan(source: source)
    }

    @Test func editedSheetWithVanishedTrackKeepsPlaylistOnCoveringTrack() async throws {
        let (root, db, scanner, source) = try rig()
        defer { try? FileManager.default.removeItem(at: root) }
        let cue = root.appendingPathComponent("disc.cue")
        try sheet().write(to: cue, atomically: true, encoding: .utf8)
        _ = try await scanner.scan(source: source)
        let segments = try await db.reader.read {
            try Track.order(Column("cue_start")).fetchAll($0)
        }
        let second = try #require(segments.last?.id)
        let playlists = PlaylistRepository(db: db)
        let playlistID = try #require(playlists.create(name: "Keep").id)
        try playlists.setTracks([second], in: playlistID)

        // Второй трек из листа убрали: его начало теперь внутри первого.
        try """
        FILE "disc.flac" WAVE
          TRACK 01 AUDIO
            TITLE "Only"
            INDEX 01 00:00:00
        """.write(to: cue, atomically: true, encoding: .utf8)
        _ = try await scanner.scan(source: source)

        let rows = try await db.reader.read { try Track.fetchAll($0) }
        #expect(rows.count == 1)
        #expect(try playlists.trackIds(in: playlistID) == [segments.first?.id].compactMap { $0 })
    }

    // MARK: - Дедупликация

    @Test func dedupDoesNotMergeDifferentFileNames() async throws {
        let (root, db, scanner, source) = try rig()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await scanner.scan(source: source)
        let actual = try #require(try await db.reader.read { try Track.fetchOne($0) })
        let other = Source(kind: .local, displayName: "Offline")
        try SourceRepository(db: db).upsert(other)
        var stranger = actual
        stranger.id = nil
        stranger.sourceId = other.id
        stranger.unavailable = true
        stranger.relativePath = "other-name.flac"  // same size and mtime, other file
        _ = try TrackRepository(db: db).insert([stranger])

        let summary = try await scanner.scan(source: source)
        #expect(summary.deduplicated == 0)
        #expect(try TrackRepository(db: db).count() == 2)
    }

    // MARK: - Репозиторий

    @Test func updateKeepsIdentityAndRewritesFields() throws {
        let db = try AppDatabase.inMemory()
        let source = Source(kind: .local, displayName: "Audit")
        try SourceRepository(db: db).upsert(source)
        let repo = TrackRepository(db: db)
        var track = try #require(
            repo.insert([
                Track(
                    sourceId: source.id, remoteId: "r1", title: "Old", duration: 1, codec: "mp3",
                    sampleRate: 0)
            ]).first)
        track.title = "New"
        track.codec = "flac"
        track.sampleRate = 96000
        try repo.update(track)
        let id = try #require(track.id)
        let stored = try #require(try repo.track(id: id))
        #expect(stored.title == "New")
        #expect(stored.codec == "flac")
        #expect(stored.sampleRate == 96000)
        #expect(try repo.count() == 1)
    }

    @Test func unavailableFlagByIdsTouchesOnlyThoseRows() throws {
        let db = try AppDatabase.inMemory()
        let source = Source(kind: .local, displayName: "Audit")
        try SourceRepository(db: db).upsert(source)
        let repo = TrackRepository(db: db)
        let ids = try repo.insert(
            (0..<3).map {
                Track(
                    sourceId: source.id, relativePath: "\($0).flac", title: "T\($0)", duration: 1,
                    codec: "flac", sampleRate: 44100)
            }
        ).compactMap(\.id)
        #expect(try repo.setUnavailable(true, ids: [ids[0], ids[2]]) == 2)
        #expect(try repo.unavailableCount() == 2)
        #expect(try repo.setUnavailable(false, ids: [ids[0]]) == 1)
        #expect(try repo.unavailableCount() == 1)
        #expect(try repo.setUnavailable(true, ids: []) == 0)
    }
}
