import EscapementCore
import Foundation
import Testing

@testable import MusicLibrary

/// Перф-тест скана (TASKS фаза 4): 10 000 файлов. Бюджет из SPEC §5.2 —
/// 50k ≤ 4 мин холодным сканом ⇒ 10k ≤ 48 с; повторный скан ≤ 15 с на 50k ⇒ ≤ 3 с.
/// Гоняется только с RUN_SCAN_PERF=1 — на каждом прогоне 10k файлов не нужны.
struct ScanPerformanceTests {
    static var enabled: Bool {
        ScannerTests.fixturesAvailable
            && ProcessInfo.processInfo.environment["RUN_SCAN_PERF"] != nil
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(10)))
    func coldScan10kWithinBudget() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Один реальный файл + APFS-клоны: полноценное чтение метаданных
        // без гигабайтов на диске.
        let seedSource = Self.smallestFixture()
        let seed = root.appendingPathComponent("seed.flac")
        try FileManager.default.copyItem(at: seedSource, to: seed)
        for album in 0..<100 {
            let dir = root.appendingPathComponent("Album \(album)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for trackNo in 0..<100 {
                try FileManager.default.copyItem(
                    at: seed, to: dir.appendingPathComponent("track-\(trackNo).flac"))
            }
        }
        try FileManager.default.removeItem(at: seed)

        let db = try AppDatabase.inMemory()
        var source = Source(kind: .local, displayName: "Perf")
        source.bookmark = try LibraryScanner.makeBookmark(for: root)
        try SourceRepository(db: db).upsert(source)

        let tmp = FileManager.default.temporaryDirectory
        let scanner = LibraryScanner(
            db: db,
            covers: try CoverCache(root: tmp.appendingPathComponent("covers-perf")),
            logURL: tmp.appendingPathComponent("scan-perf.log"))

        let coldStart = ContinuousClock.now
        let cold = try await scanner.scan(source: source)
        let coldTime = ContinuousClock.now - coldStart
        #expect(cold.added == 10_000)
        #expect(coldTime < .seconds(48), "cold scan took \(coldTime), budget 48 s")

        let warmStart = ContinuousClock.now
        let warm = try await scanner.scan(source: source)
        let warmTime = ContinuousClock.now - warmStart
        #expect(warm.unchanged == 10_000)
        #expect(warmTime < .seconds(3), "warm rescan took \(warmTime), budget 3 s")
    }

    private static func smallestFixture() -> URL {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: ScannerTests.fixturesDir, includingPropertiesForKeys: [.fileSizeKey]))?
            .filter { $0.pathExtension == "flac" } ?? []
        return files.min { a, b in
            let sa = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let sb = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sa < sb
        }!
    }
}
