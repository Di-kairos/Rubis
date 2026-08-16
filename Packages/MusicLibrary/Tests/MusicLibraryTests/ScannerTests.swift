import EscapementCore
import Foundation
import Testing

@testable import MusicLibrary

/// Тесты сканера. Аудио-фикстуры берутся из Fixtures/ проекта (генерятся
/// Tools/make-fixtures.sh, в git не попадают) — если их нет, тесты скипаются.
struct ScannerTests {
    static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MusicLibraryTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // MusicLibrary
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Fixtures")

    static var fixturesAvailable: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: fixturesDir.path).contains {
            $0.hasSuffix(".flac")
        }) ?? false
    }

    /// Собирает временную «библиотеку» из N копий фикстур.
    private func makeLibrary(copies: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Album A"), withIntermediateDirectories: true)
        let sources = try FileManager.default.contentsOfDirectory(
            at: Self.fixturesDir, includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "flac" }
        for i in 0..<copies {
            let src = sources[i % sources.count]
            let dst = root.appendingPathComponent("Album A/track-\(i).flac")
            try FileManager.default.copyItem(at: src, to: dst)
        }
        return root
    }

    /// Пустая папка под второй источник.
    private func makeEmptyLibrary() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeScanner(_ db: TestDatabase) throws -> LibraryScanner {
        let tmp = FileManager.default.temporaryDirectory
        return LibraryScanner(
            db: db,
            covers: try CoverCache(
                root: tmp.appendingPathComponent("covers-\(UUID().uuidString)")),
            logURL: tmp.appendingPathComponent("scan-test-\(UUID().uuidString).log"))
    }

    @Test(.enabled(if: fixturesAvailable)) func scanAddsTracksIncrementallyAndRemoves() async throws
    {
        let root = try makeLibrary(copies: 6)
        defer { try? FileManager.default.removeItem(at: root) }

        let db = try AppDatabase.inMemory()
        var source = Source(kind: .local, displayName: "Test")
        source.bookmark = try LibraryScanner.makeBookmark(for: root)
        try SourceRepository(db: db).upsert(source)

        let scanner = try makeScanner(db)

        // Холодный скан: всё добавлено
        let first = try await scanner.scan(source: source)
        #expect(first.added == 6)
        #expect(first.failed.isEmpty)
        #expect(try TrackRepository(db: db).count() == 6)

        // Повторный скан без изменений: ничего не читается заново
        let second = try await scanner.scan(source: source)
        #expect(second.added == 0)
        #expect(second.updated == 0)
        #expect(second.unchanged == 6)

        // Удаление файла помечает трек недоступным, но не выкидывает из библиотеки
        try FileManager.default.removeItem(
            at: root.appendingPathComponent("Album A/track-0.flac"))
        let third = try await scanner.scan(source: source)
        #expect(third.unavailable == 1)
        #expect(try TrackRepository(db: db).count() == 6)
        #expect(try TrackRepository(db: db).unavailableCount() == 1)
    }

    @Test(.enabled(if: fixturesAvailable)) func movedFileKeepsIdentity() async throws {
        let root = try makeLibrary(copies: 2)
        defer { try? FileManager.default.removeItem(at: root) }

        let db = try AppDatabase.inMemory()
        var source = Source(kind: .local, displayName: "Test")
        source.bookmark = try LibraryScanner.makeBookmark(for: root)
        try SourceRepository(db: db).upsert(source)

        let scanner = try makeScanner(db)
        _ = try await scanner.scan(source: source)

        let trackRepo = TrackRepository(db: db)
        let moved = try #require(
            try trackRepo.tracks(ids: [1, 2]).first { $0.relativePath == "Album A/track-0.flac" })
        // Трек в плейлисте — он обязан пережить перенос файла
        let playlistRepo = PlaylistRepository(db: db)
        let playlist = try playlistRepo.create(name: "Mix")
        try playlistRepo.setTracks([moved.id!], in: playlist.id!)

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Album B"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: root.appendingPathComponent("Album A/track-0.flac"),
            to: root.appendingPathComponent("Album B/track-0.flac"))

        let summary = try await scanner.scan(source: source)
        #expect(summary.moved == 1)
        #expect(summary.unavailable == 0)
        #expect(try trackRepo.count() == 2)
        #expect(try playlistRepo.trackIds(in: playlist.id!) == [moved.id!])
        #expect(try trackRepo.track(id: moved.id!)?.relativePath == "Album B/track-0.flac")
    }

    /// Переезд файла между источниками (папки «направлений музыки»):
    /// старый источник просканирован первым — трек обязан сменить источник,
    /// а не раздвоиться.
    @Test(.enabled(if: fixturesAvailable)) func fileMovedToAnotherSourceKeepsIdentity()
        async throws
    {
        let ambient = try makeLibrary(copies: 2)
        let electro = try makeEmptyLibrary()
        defer {
            try? FileManager.default.removeItem(at: ambient)
            try? FileManager.default.removeItem(at: electro)
        }

        let db = try AppDatabase.inMemory()
        let repo = SourceRepository(db: db)
        var first = Source(kind: .local, displayName: "AMBIENT")
        first.bookmark = try LibraryScanner.makeBookmark(for: ambient)
        try repo.upsert(first)
        var second = Source(kind: .local, displayName: "ELECTRO")
        second.bookmark = try LibraryScanner.makeBookmark(for: electro)
        try repo.upsert(second)

        let scanner = try makeScanner(db)
        _ = try await scanner.scan(source: first)
        _ = try await scanner.scan(source: second)

        let trackRepo = TrackRepository(db: db)
        let moving = try #require(
            try trackRepo.tracks(ids: [1, 2]).first { $0.relativePath == "Album A/track-0.flac" })
        let playlistRepo = PlaylistRepository(db: db)
        let playlist = try playlistRepo.create(name: "Mix")
        try playlistRepo.setTracks([moving.id!], in: playlist.id!)

        try FileManager.default.createDirectory(
            at: electro.appendingPathComponent("Album A"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: ambient.appendingPathComponent("Album A/track-0.flac"),
            to: electro.appendingPathComponent("Album A/track-0.flac"))

        #expect(try await scanner.scan(source: first).unavailable == 1)
        let arrival = try await scanner.scan(source: second)
        #expect(arrival.moved == 1)
        #expect(arrival.added == 0)

        // Один файл — один трек, под новым источником и со своим id.
        #expect(try trackRepo.count() == 2)
        #expect(try trackRepo.unavailableCount() == 0)
        #expect(try trackRepo.track(id: moving.id!)?.sourceId == second.id)
        #expect(try playlistRepo.trackIds(in: playlist.id!) == [moving.id!])
    }

    /// Тот же переезд, но новый источник просканирован раньше старого:
    /// файл успевает войти новой строкой, старая остаётся недоступной.
    /// Уборка обязана снять двойника.
    @Test(.enabled(if: fixturesAvailable)) func unluckyScanOrderLeavesNoGhost() async throws {
        let ambient = try makeLibrary(copies: 2)
        let electro = try makeEmptyLibrary()
        defer {
            try? FileManager.default.removeItem(at: ambient)
            try? FileManager.default.removeItem(at: electro)
        }

        let db = try AppDatabase.inMemory()
        let repo = SourceRepository(db: db)
        var first = Source(kind: .local, displayName: "AMBIENT")
        first.bookmark = try LibraryScanner.makeBookmark(for: ambient)
        try repo.upsert(first)
        var second = Source(kind: .local, displayName: "ELECTRO")
        second.bookmark = try LibraryScanner.makeBookmark(for: electro)
        try repo.upsert(second)

        let scanner = try makeScanner(db)
        _ = try await scanner.scan(source: first)

        try FileManager.default.createDirectory(
            at: electro.appendingPathComponent("Album A"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: ambient.appendingPathComponent("Album A/track-0.flac"),
            to: electro.appendingPathComponent("Album A/track-0.flac"))

        // Новый источник первым: старая строка ещё числится доступной,
        // поэтому файл входит как новый трек.
        #expect(try await scanner.scan(source: second).added == 1)
        let cleanup = try await scanner.scan(source: first)
        #expect(cleanup.unavailable == 1)
        #expect(cleanup.deduplicated == 1)

        let trackRepo = TrackRepository(db: db)
        #expect(try trackRepo.count() == 2)
        #expect(try trackRepo.unavailableCount() == 0)
    }

    @Test(.enabled(if: fixturesAvailable)) func returningFileClearsUnavailable() async throws {
        let root = try makeLibrary(copies: 2)
        defer { try? FileManager.default.removeItem(at: root) }

        let db = try AppDatabase.inMemory()
        var source = Source(kind: .local, displayName: "Test")
        source.bookmark = try LibraryScanner.makeBookmark(for: root)
        try SourceRepository(db: db).upsert(source)

        let scanner = try makeScanner(db)
        _ = try await scanner.scan(source: source)

        // Файл «уехал вместе с томом» и вернулся тем же самым
        let path = root.appendingPathComponent("Album A/track-0.flac")
        let stash = FileManager.default.temporaryDirectory
            .appendingPathComponent("stash-\(UUID().uuidString).flac")
        try FileManager.default.moveItem(at: path, to: stash)
        #expect(try await scanner.scan(source: source).unavailable == 1)

        try FileManager.default.moveItem(at: stash, to: path)
        let back = try await scanner.scan(source: source)
        #expect(back.restored == 1)
        #expect(try TrackRepository(db: db).unavailableCount() == 0)
    }

    @Test(.enabled(if: fixturesAvailable)) func brokenFileDoesNotAbortScan() async throws {
        let root = try makeLibrary(copies: 3)
        defer { try? FileManager.default.removeItem(at: root) }
        // битый файл: мусор с расширением flac
        try Data("not audio at all".utf8).write(
            to: root.appendingPathComponent("Album A/broken.flac"))

        let db = try AppDatabase.inMemory()
        var source = Source(kind: .local, displayName: "Test")
        source.bookmark = try LibraryScanner.makeBookmark(for: root)
        try SourceRepository(db: db).upsert(source)

        let summary = try await makeScanner(db).scan(source: source)
        #expect(summary.added == 3)
        #expect(summary.failed == ["Album A/broken.flac"])
    }

    @Test(.enabled(if: fixturesAvailable)) func progressStreamReportsFinish() async throws {
        let root = try makeLibrary(copies: 2)
        defer { try? FileManager.default.removeItem(at: root) }

        let db = try AppDatabase.inMemory()
        var source = Source(kind: .local, displayName: "Test")
        source.bookmark = try LibraryScanner.makeBookmark(for: root)
        try SourceRepository(db: db).upsert(source)

        var finished: ScanSummary?
        for try await progress in try makeScanner(db).scanStream(source: source) {
            if case .finished(let summary) = progress { finished = summary }
        }
        #expect(finished?.added == 2)
    }
}

/// Выбор обложки в папке альбома (файлы, а не встроенный тег).
struct FolderArtTests {
    /// Кладёт картинки заданного размера в свежую временную папку.
    private func makeDirectory(_ files: [(name: String, bytes: Int)]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("folder-art-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            try Data(repeating: 0x41, count: file.bytes)
                .write(to: root.appendingPathComponent(file.name))
        }
        return root
    }

    @Test func filterOrderBeatsFileSize() throws {
        let root = try makeDirectory([
            ("back.jpg", 4000), ("front.jpg", 100), ("cover.png", 8000), ("scan.png", 9000),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        // front важнее cover, и важнее размера: 100 байт побеждают 8000.
        #expect(LibraryScanner.folderArt(in: root)?.count == 100)
    }

    @Test func withoutFilterMatchPicksBiggestImage() throws {
        let root = try makeDirectory([("scan1.jpg", 300), ("scan2.jpg", 700), ("notes.txt", 5000)])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(LibraryScanner.folderArt(in: root)?.count == 700)
    }

    @Test func noImagesGivesNil() throws {
        let root = try makeDirectory([("notes.txt", 10)])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(LibraryScanner.folderArt(in: root) == nil)
    }

    @Test func plainNameBeatsQualifiedAndNumberedScans() throws {
        let root = try makeDirectory([
            ("Nocturnal (back).jpg", 9000), ("Nocturnal 003.jpg", 8000),
            ("Nocturnal.jpg", 200),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        // Лицо диска подписано без уточнения и без номера страницы — и весит
        // меньше разворота буклета.
        #expect(LibraryScanner.folderArt(in: root)?.count == 200)
    }

    @Test func coverIsTakenFromTheScansSubfolder() throws {
        let root = try makeDirectory([("Nocturnal.cue", 100)])
        defer { try? FileManager.default.removeItem(at: root) }
        let scans = root.appendingPathComponent("Сканы")
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 5000)
            .write(to: scans.appendingPathComponent("Nocturnal (back).jpg"))
        try Data(repeating: 0x41, count: 300)
            .write(to: scans.appendingPathComponent("Nocturnal.jpg"))

        #expect(LibraryScanner.folderArt(in: root) == nil)
        #expect(LibraryScanner.folderArtInSubdirectories(of: root)?.count == 300)
    }
}
