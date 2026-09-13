import EscapementCore
import Foundation
import GRDB
import Testing

@testable import MusicLibrary

struct AuditFollowupTests {
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
    @Test func oneCueFrameEditMustUpdateTheStoredBoundary() async throws {
        let (root, db, scanner, source) = try rig()
        defer { try? FileManager.default.removeItem(at: root) }
        let cue = root.appendingPathComponent("disc.cue")
        try sheet().write(to: cue, atomically: true, encoding: .utf8)
        _ = try await scanner.scan(source: source)
        try sheet(second: "00:02:01").write(to: cue, atomically: true, encoding: .utf8)
        let result = try await scanner.scan(source: source)
        let rows = try await db.reader.read { try Track.order(Column("cue_start")).fetchAll($0) }
        let expected = 2 + 1.0 / 75
        let actual = try #require(rows.last?.cueStart)
        print(
            "FOLLOWUP CUE frame: unchanged=\(result.unchanged), actual=\(actual), expected=\(expected)"
        )
        #expect(abs(actual - expected) < 1e-9)
    }

    /// Смена исполнителя дорожки при тех же названиях и границах тоже
    /// перечитывается (остаток приёмки R06).
    @Test func performerEditIsPickedUp() async throws {
        let (root, db, scanner, source) = try rig()
        defer { try? FileManager.default.removeItem(at: root) }
        let cue = root.appendingPathComponent("disc.cue")
        try sheet().write(to: cue, atomically: true, encoding: .utf8)
        _ = try await scanner.scan(source: source)
        try sheet().replacingOccurrences(
            of: "PERFORMER \"Audit Artist\"", with: "PERFORMER \"Other Artist\""
        )
        .write(to: cue, atomically: true, encoding: .utf8)
        let result = try await scanner.scan(source: source)
        let names = try await db.reader.read { db -> [String] in
            try String.fetchAll(
                db,
                sql:
                    "SELECT artist.name FROM track JOIN artist ON artist.id = track.artist_id ORDER BY cue_start"
            )
        }
        #expect(result.unchanged == 0)
        #expect(names == ["Other Artist", "Other Artist"])
        // И повторный скан без правок ничего не перечитывает.
        #expect(try await scanner.scan(source: source).unchanged == 2)
    }

    /// Два настоящих WAV с разным PCM, но одинаковыми именем, размером и mtime.
    /// F03: без сохранённого отпечатка содержимого доказать тождество нельзя —
    /// ждёт решения владельца (миграция `track.content_hash` либо явное
    /// принятие риска). До него тест в наборе, но выключен.
    @Test(.disabled("F03: ждёт решения владельца об отпечатке содержимого"))
    func differentAudioMustNotReplaceAnOfflinePlaylistEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "followup-twins-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("A")
        let b = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let bytesA = wav(sample: 1234)
        let bytesB = wav(sample: -4321)
        #expect(bytesA.count == bytesB.count)
        #expect(bytesA != bytesB)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        for (directory, bytes) in [(a, bytesA), (b, bytesB)] {
            let url = directory.appendingPathComponent("disc.wav")
            try bytes.write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: stamp], ofItemAtPath: url.path)
        }
        let db = try AppDatabase.inMemory()
        var sourceA = Source(kind: .local, displayName: "A")
        sourceA.bookmark = try LibraryScanner.makeBookmark(for: a)
        var sourceB = Source(kind: .local, displayName: "B")
        sourceB.bookmark = try LibraryScanner.makeBookmark(for: b)
        let sources = SourceRepository(db: db)
        try sources.upsert(sourceA)
        try sources.upsert(sourceB)
        let scanner = LibraryScanner(
            db: db, covers: try CoverCache(root: root.appendingPathComponent("covers")),
            logURL: root.appendingPathComponent("scan.log"))
        _ = try await scanner.scan(source: sourceB)
        let before = try #require(try await db.reader.read { try Track.fetchOne($0) })
        let originalID = try #require(before.id)
        let playlists = PlaylistRepository(db: db)
        let pid = try #require(playlists.create(name: "Keep B").id)
        try playlists.setTracks([originalID], in: pid)
        // A появился, пока B ещё считался доступным: это две строки в базе.
        _ = try await scanner.scan(source: sourceA)
        // Том B теперь недоступен: повторный скан A запускает уборку двойников.
        try await db.writer.write { database in
            try database.execute(
                sql: "UPDATE track SET unavailable = 1 WHERE id = ?", arguments: [originalID])
        }
        let summary = try await scanner.scan(source: sourceA)
        let linked = try playlists.trackIds(in: pid)
        let survivors = try await db.reader.read { try Track.fetchAll($0) }
        print(
            "FOLLOWUP false twin: merged=\(summary.deduplicated), originalID=\(originalID), playlistIDs=\(linked), survivors=\(survivors.map(\.sourceId))"
        )
        #expect(summary.deduplicated == 0)
        #expect(linked == [originalID])
        #expect(survivors.contains { $0.id == originalID && $0.sourceId == sourceB.id })
    }

    private func wav(sample: Int16) -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) {
            var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func u32(_ value: UInt32) {
            var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        let frames: UInt32 = 44100
        text("RIFF"); u32(36 + frames * 2); text("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(44100); u32(88200); u16(2); u16(16)
        text("data"); u32(frames * 2)
        for _ in 0..<frames { u16(UInt16(bitPattern: sample)) }
        return data
    }
}
