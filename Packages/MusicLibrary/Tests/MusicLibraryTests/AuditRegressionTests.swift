import EscapementCore
import Foundation
import GRDB
import Testing

@testable import MusicLibrary

struct AuditRegressionTests {
    private func rig() throws -> (URL, TestDatabase, LibraryScanner, Source) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "audit-rip-\(UUID())")
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
    private func sheet(_ title: String = "Original", second: String = "00:02:00") -> String {
        """
        TITLE "Audit Album"
        PERFORMER "Audit Artist"
        FILE "disc.flac" WAVE
          TRACK 01 AUDIO
            TITLE "\(title)"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Second"
            INDEX 01 \(second)
        """
    }
    @Test func cueEditWithSameCountMustUpdate() async throws {
        let (root, db, scanner, source) = try rig()
        defer { try? FileManager.default.removeItem(at: root) }
        let cue = root.appendingPathComponent("disc.cue")
        try sheet().write(to: cue, atomically: true, encoding: .utf8)
        _ = try await scanner.scan(source: source)
        try sheet("Changed", second: "00:03:00").write(to: cue, atomically: true, encoding: .utf8)
        let result = try await scanner.scan(source: source)
        let rows = try await db.reader.read { try Track.order(Column("cue_start")).fetchAll($0) }
        print(
            "AUDIT cue edit: unchanged=\(result.unchanged), titles=\(rows.map(\.title)), starts=\(rows.map(\.cueStart))"
        )
        #expect(rows.first?.title == "Changed")
        #expect(rows.last?.cueStart == 3)
    }
    @Test func removedCueMustBecomeOneStableTrack() async throws {
        let (root, db, scanner, source) = try rig()
        defer { try? FileManager.default.removeItem(at: root) }
        let cue = root.appendingPathComponent("disc.cue")
        try sheet().write(to: cue, atomically: true, encoding: .utf8)
        _ = try await scanner.scan(source: source)
        try FileManager.default.removeItem(at: cue)
        _ = try await scanner.scan(source: source)
        let rows = try await db.reader.read { try Track.fetchAll($0) }
        print("AUDIT removed CUE: rows=\(rows.count), starts=\(rows.map(\.cueStart))")
        #expect(rows.count == 1)
        _ = try await scanner.scan(source: source)
    }
    @Test func automaticDedupMustPreservePlaylist() async throws {
        let (root, db, scanner, source) = try rig()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await scanner.scan(source: source)
        let actual = try #require(try await db.reader.read { try Track.fetchOne($0) })
        let other = Source(kind: .local, displayName: "Offline source")
        try SourceRepository(db: db).upsert(other)
        var orphan = actual
        orphan.id = nil; orphan.sourceId = other.id; orphan.unavailable = true
        let saved = try #require(TrackRepository(db: db).insert([orphan]).first)
        let repo = PlaylistRepository(db: db)
        let playlistID = try #require(repo.create(name: "Keep me").id)
        try repo.setTracks([try #require(saved.id)], in: playlistID)
        _ = try await scanner.scan(source: source)
        let ids = try repo.trackIds(in: playlistID)
        print("AUDIT dedup: playlist IDs=\(ids)")
        #expect(ids.count == 1)
    }
    @Test func appendAfterCascadeMustRemainPossible() throws {
        let db = try AppDatabase.inMemory()
        let source = Source(kind: .local, displayName: "Audit")
        try SourceRepository(db: db).upsert(source)
        let tracks = try TrackRepository(db: db).insert(
            (0..<4).map {
                Track(
                    sourceId: source.id, relativePath: "\($0).flac", title: "Track \($0)",
                    duration: 5, codec: "flac", sampleRate: 44100)
            })
        let ids = tracks.compactMap(\.id)
        let repo = PlaylistRepository(db: db)
        let pid = try #require(repo.create(name: "Audit").id)
        try repo.setTracks(Array(ids.prefix(3)), in: pid)
        try TrackRepository(db: db).delete(ids: [ids[1]])
        try repo.append([ids[3]], to: pid)
        #expect(try repo.trackIds(in: pid) == [ids[0], ids[2], ids[3]])
    }
    @Test func cueMustRejectNonFiniteTime() throws {
        let parsed = try #require(CueSheet.parse(sheet(second: "inf:00:00")))
        print("AUDIT CUE nonfinite start=\(parsed.tracks.last?.start ?? 0)")
        #expect(parsed.tracks.allSatisfy { $0.start.isFinite })
    }
}
