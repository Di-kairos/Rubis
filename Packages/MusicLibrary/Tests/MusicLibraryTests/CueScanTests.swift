import EscapementCore
import Foundation
import GRDB
import Testing

@testable import MusicLibrary

/// Скан рипа «диск одним файлом + CUE» (D-013). Аудио берётся из Fixtures/
/// (Tools/make-fixtures.sh); нет фикстур — тесты скипаются.
struct CueScanTests {

    private static var fixture: URL? {
        let dir = ScannerTests.fixturesDir
        return
            (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "flac" }
    }

    static var fixturesAvailable: Bool { fixture != nil }

    /// Папка с диском одним файлом и листом на три дорожки. Фикстура длиной
    /// 5 секунд, поэтому границы — внутри неё.
    private func makeRip(sheet: String? = nil) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-scan-\(UUID().uuidString)")
        let album = root.appendingPathComponent("Album")
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: #require(Self.fixture), to: album.appendingPathComponent("disc.flac"))
        let text =
            sheet
                ?? """
                PERFORMER "Miles Davis"
                TITLE "Kind of Blue"
                REM DATE 1959
                FILE "disc.flac" WAVE
                  TRACK 01 AUDIO
                    TITLE "So What"
                    INDEX 01 00:00:00
                  TRACK 02 AUDIO
                    TITLE "Freddie Freeloader"
                    INDEX 01 00:01:00
                  TRACK 03 AUDIO
                    TITLE "Blue in Green"
                    PERFORMER "Bill Evans"
                    INDEX 01 00:03:00
                """
        try text.write(
            to: album.appendingPathComponent("disc.cue"), atomically: true, encoding: .utf8)
        return root
    }

    private func makeScanner(_ db: TestDatabase) throws -> LibraryScanner {
        let tmp = FileManager.default.temporaryDirectory
        return LibraryScanner(
            db: db,
            covers: try CoverCache(root: tmp.appendingPathComponent("covers-\(UUID().uuidString)")),
            logURL: tmp.appendingPathComponent("cue-scan-\(UUID().uuidString).log"))
    }

    private func source(at root: URL, db: TestDatabase) throws -> Source {
        var source = Source(kind: .local, displayName: "Rip")
        source.bookmark = try LibraryScanner.makeBookmark(for: root)
        try SourceRepository(db: db).upsert(source)
        return source
    }

    private func tracks(_ db: TestDatabase) async throws -> [Track] {
        try await db.reader.read { database in
            try Track.order(Column("cue_start")).fetchAll(database)
        }
    }

    @Test(.enabled(if: fixturesAvailable)) func aDiscInOneFileBecomesItsTracks() async throws {
        let root = try makeRip()
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AppDatabase.inMemory()
        let source = try source(at: root, db: db)

        _ = try await makeScanner(db).scan(source: source)

        let tracks = try await tracks(db)
        #expect(tracks.count == 3)
        #expect(tracks.map(\.title) == ["So What", "Freddie Freeloader", "Blue in Green"])
        // Все три живут в одном файле — этого прежняя схема не позволяла.
        #expect(Set(tracks.map(\.relativePath)) == ["Album/disc.flac"])
        // 00:01:00 — одна секунда: в CUE время меряется MM:SS:FF.
        #expect(tracks.map(\.cueStart) == [0, 1, 3])
        #expect(tracks[0].cueEnd == 1)
        #expect(tracks[1].duration == 2)
        // У последней конца нет: она играет до конца файла, и её длительность
        // считается от длины самого файла.
        #expect(tracks[2].cueEnd == nil)
    }

    @Test(.enabled(if: fixturesAvailable)) func albumComesFromTheSheetNotTheTags() async throws {
        let root = try makeRip()
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AppDatabase.inMemory()
        let source = try source(at: root, db: db)

        _ = try await makeScanner(db).scan(source: source)

        let album = try await db.reader.read { try Album.fetchOne($0) }
        #expect(album?.title == "Kind of Blue")
        #expect(album?.albumArtist == "Miles Davis")
        #expect(album?.year == 1959)
        // Исполнитель дорожки перекрывает исполнителя диска.
        let evans = try await db.reader.read { database in
            try Artist.filter(Column("name") == "Bill Evans").fetchOne(database)
        }
        #expect(evans != nil)
    }

    @Test(.enabled(if: fixturesAvailable)) func rescanChangesNothing() async throws {
        let root = try makeRip()
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AppDatabase.inMemory()
        let source = try source(at: root, db: db)
        let scanner = try makeScanner(db)

        _ = try await scanner.scan(source: source)
        let first = try await tracks(db)
        let summary = try await scanner.scan(source: source)

        let second = try await tracks(db)
        #expect(summary.added == 0)
        #expect(summary.unchanged == 3)
        // Те же строки: id переживают повторный скан, значит переживут его
        // плейлисты и история.
        #expect(first.map(\.id) == second.map(\.id))
    }

    @Test(.enabled(if: fixturesAvailable)) func editingTheSheetRewritesTheTracks() async throws {
        let root = try makeRip()
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AppDatabase.inMemory()
        let source = try source(at: root, db: db)
        let scanner = try makeScanner(db)
        _ = try await scanner.scan(source: source)
        let before = try await tracks(db)

        // Лист урезали до двух дорожек, у первой поменялось название.
        try """
        PERFORMER "Miles Davis"
        TITLE "Kind of Blue"
        FILE "disc.flac" WAVE
          TRACK 01 AUDIO
            TITLE "So What (take 2)"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Freddie Freeloader"
            INDEX 01 00:01:00
        """.write(
            to: root.appendingPathComponent("Album/disc.cue"), atomically: true, encoding: .utf8)

        _ = try await scanner.scan(source: source)

        let after = try await tracks(db)
        #expect(after.count == 2)
        #expect(after[0].title == "So What (take 2)")
        // Начало дорожки не изменилось — строка та же, а не новая.
        #expect(after[0].id == before[0].id)
        #expect(after[1].cueEnd == nil)
    }

    @Test(.enabled(if: fixturesAvailable)) func aSheetWithoutItsAudioIsIgnored() async throws {
        let root = try makeRip()
        defer { try? FileManager.default.removeItem(at: root) }
        // Лист ссылается на .wav, которого рядом нет, — обычное дело у рипов.
        try """
        FILE "disc.wav" WAVE
          TRACK 01 AUDIO
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            INDEX 01 00:01:00
        """.write(
            to: root.appendingPathComponent("Album/disc.cue"), atomically: true, encoding: .utf8)
        let db = try AppDatabase.inMemory()
        let source = try source(at: root, db: db)

        _ = try await makeScanner(db).scan(source: source)

        let tracks = try await tracks(db)
        #expect(tracks.count == 1)
        #expect(tracks[0].cueStart == nil)
    }

    @Test(.enabled(if: fixturesAvailable)) func aSheetAddedLaterSplitsTheFileOnRescan()
        async throws
    {
        // Файл уже в библиотеке одним треком; лист появляется рядом позже.
        // Размер и время файла не изменились — только количество строк.
        let root = try makeRip(sheet: "")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("Album/disc.cue"))
        let db = try AppDatabase.inMemory()
        let source = try source(at: root, db: db)
        let scanner = try makeScanner(db)
        _ = try await scanner.scan(source: source)
        #expect(try await tracks(db).count == 1)

        try """
        FILE "disc.flac" WAVE
          TRACK 01 AUDIO
            TITLE "One"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Two"
            INDEX 01 00:02:00
        """.write(
            to: root.appendingPathComponent("Album/disc.cue"), atomically: true, encoding: .utf8)

        _ = try await scanner.scan(source: source)

        let tracks = try await tracks(db)
        #expect(tracks.count == 2)
        #expect(tracks.map(\.title) == ["One", "Two"])
    }
}
