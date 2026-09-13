import EscapementCore
import Foundation
import GRDB
import Testing

@testable import MusicLibrary

struct ReauditRegressionTests {
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
    /// Архив/синхронизация может сохранить прежнюю дату изменённого CUE.
    @Test func cueEditWithPreservedMtimeMustUpdate() async throws {
        let (root, db, scanner, source) = try rig()
        defer { try? FileManager.default.removeItem(at: root) }
        let cue = root.appendingPathComponent("disc.cue")
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        try sheet().write(to: cue, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: cue.path)
        _ = try await scanner.scan(source: source)
        try sheet("Changed", second: "00:03:00").write(to: cue, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: cue.path)
        let result = try await scanner.scan(source: source)
        let rows = try await db.reader.read { try Track.order(Column("cue_start")).fetchAll($0) }
        print(
            "REAUDIT preserved mtime: unchanged=\(result.unchanged), titles=\(rows.map(\.title)), starts=\(rows.map(\.cueStart))"
        )
        #expect(rows.first?.title == "Changed")
        #expect(rows.last?.cueStart == 3)
    }
}
