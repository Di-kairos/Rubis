import EscapementCore
import Foundation
import Testing

@testable import MusicLibrary

/// Phase 2 acceptance (TASKS): 100 000 tracks inserted, FTS5 search under 50 ms.
struct PerformanceTests {
    @Test(.timeLimit(.minutes(5))) func fts5SearchOn100kTracksUnder50ms() throws {
        let db = try AppDatabase.inMemory()
        let source = Source(kind: .local, displayName: "Perf")
        try SourceRepository(db: db).upsert(source)

        // Batched insert of 100k generated tracks (500 per transaction, SPEC §5.2).
        let total = 100_000
        let batchSize = 500
        let words = [
            "Blue", "Green", "Night", "Train", "River", "Silver", "Ghost", "Echo",
            "Vega", "Stone", "Amber", "Юность", "Кассиопея", "Träume", "Été",
        ]
        var counter = 0
        for batchStart in stride(from: 0, to: total, by: batchSize) {
            try db.writer.write { database in
                for i in batchStart..<min(batchStart + batchSize, total) {
                    counter = i
                    var track = Track(
                        sourceId: source.id,
                        relativePath: "gen/\(i).flac",
                        title: "\(words[i % words.count]) \(words[(i / 7) % words.count]) \(i)",
                        duration: 200,
                        codec: "flac",
                        sampleRate: 44_100)
                    try track.insert(database)
                }
            }
        }
        _ = counter
        #expect(try TrackRepository(db: db).count() == total)

        let repo = TrackRepository(db: db)
        // Warm-up query compiles statements and pages the index.
        _ = try repo.search("Blue")

        let queries = ["Blue", "Кассиопея", "Träume", "Silver Night", "Ec"]
        for query in queries {
            let start = ContinuousClock.now
            let hits = try repo.search(query)
            let elapsed = ContinuousClock.now - start
            #expect(!hits.isEmpty, "query '\(query)' returned nothing")
            #expect(
                elapsed < .milliseconds(50),
                "query '\(query)' took \(elapsed) — budget is 50 ms")
        }
    }

    /// Раздел Tracks на 100k: две операции на пути пользователя — загрузка списка
    /// с именами и пересортировка по клику на заголовок. Обе идут вне MainActor,
    /// поэтому это бюджет «когда появится список», а не бюджет кадра.
    ///
    /// Замер на M5 Max, release: загрузка 1.56 с, сортировка ≤ 0.4 с.
    /// В debug те же операции медленнее в 4-5 раз — бюджеты разведены по конфигурации,
    /// иначе debug-порог пришлось бы задрать до бессмысленного.
    ///
    /// Оговорка: БД здесь in-memory, в проде — файловый `DatabasePool`, так что
    /// цифра загрузки оптимистична. Как защита от регрессий этого достаточно;
    /// живой замер на 100k-библиотеке — ручной пункт.
    @Test(.timeLimit(.minutes(5))) func tracksSectionOn100kStaysWithinBudget() throws {
        #if DEBUG
        let loadBudget = Duration.seconds(10)
        let sortBudget = Duration.milliseconds(1_500)
        #else
        let loadBudget = Duration.seconds(2)
        let sortBudget = Duration.milliseconds(400)
        #endif

        let db = try AppDatabase.inMemory()
        try seedLibrary(db, tracks: 100_000, artists: 2_000, albums: 10_000)
        let repo = TrackRepository(db: db)

        let loadStart = ContinuousClock.now
        let rows = try repo.allWithNames()
        let load = ContinuousClock.now - loadStart
        #expect(rows.count == 100_000)
        #expect(load < loadBudget, "allWithNames on 100k took \(load) — budget is \(loadBudget)")

        for field in TrackSort.allCases {
            let start = ContinuousClock.now
            // Ровно то, что делает раздел Tracks на клик по заголовку:
            // сортировка плюс словарь позиций для номеров строк.
            let sorted = TrackSort.sorted(rows, by: field, ascending: false)
            let positions = Dictionary(
                sorted.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            let elapsed = ContinuousClock.now - start
            #expect(sorted.count == rows.count)
            #expect(positions.count == rows.count)
            #expect(
                elapsed < sortBudget,
                "sort by \(field) took \(elapsed) — budget is \(sortBudget)")
        }
    }

    /// Группы Artists/Albums в поиске бьются по каждому нажатию клавиши, поэтому
    /// живут в том же бюджете 50 мс, что и FTS по трекам (SPEC §12).
    @Test(.timeLimit(.minutes(5))) func groupedSearchOn100kUnder50ms() throws {
        let db = try AppDatabase.inMemory()
        try seedLibrary(db, tracks: 100_000, artists: 2_000, albums: 10_000)
        let artistRepo = ArtistRepository(db: db)
        let albumRepo = AlbumRepository(db: db)
        // Прогрев: первый запрос компилирует statement и поднимает страницы индекса.
        _ = try artistRepo.search("art")
        _ = try albumRepo.search("alb")

        for query in ["a", "artist 1", "album 42", "zzz"] {
            let artistStart = ContinuousClock.now
            _ = try artistRepo.search(query)
            let artistElapsed = ContinuousClock.now - artistStart
            #expect(
                artistElapsed < .milliseconds(50),
                "artist search '\(query)' took \(artistElapsed) — budget is 50 ms")

            let albumStart = ContinuousClock.now
            _ = try albumRepo.search(query)
            let albumElapsed = ContinuousClock.now - albumStart
            #expect(
                albumElapsed < .milliseconds(50),
                "album search '\(query)' took \(albumElapsed) — budget is 50 ms")
        }
    }

    /// Не тест, а генератор фикстуры: пишет файловую библиотеку на 100k треков,
    /// чтобы можно было руками померить fps скролла в Instruments (последний
    /// пункт acceptance фазы 5). Приложение в DEBUG берёт её через `RUBIS_DB_PATH`.
    ///
    ///     RUBIS_GENERATE_LARGE_LIBRARY=/tmp/rubis-100k/library.sqlite \
    ///       swift test --filter generateLargeLibraryFixture
    ///
    /// Размер задаётся `RUBIS_LARGE_LIBRARY_TRACKS` (по умолчанию 100 000) —
    /// 50 000 нужны для проверки бюджета памяти из SPEC §12.
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["RUBIS_GENERATE_LARGE_LIBRARY"] != nil),
        .timeLimit(.minutes(5)))
    func generateLargeLibraryFixture() throws {
        let path = ProcessInfo.processInfo.environment["RUBIS_GENERATE_LARGE_LIBRARY"] ?? ""
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)

        let count =
            ProcessInfo.processInfo.environment["RUBIS_LARGE_LIBRARY_TRACKS"]
            .flatMap(Int.init) ?? 100_000
        let db = try AppDatabase(path: path)
        try seedLibrary(db, tracks: count, artists: 2_000, albums: 10_000)
        #expect(try TrackRepository(db: db).count() == count)
    }

    /// Библиотека с настоящими связями artist/album — иначе join в запросе холостой.
    private func seedLibrary(
        _ db: any DatabaseAccess, tracks: Int, artists: Int, albums: Int
    ) throws {
        let source = Source(kind: .local, displayName: "Perf")
        try SourceRepository(db: db).upsert(source)
        let artistIds = try db.writer.write { database -> [Int64] in
            try (0..<artists).map { index in
                var artist = Artist(name: "Artist \(index)", sortName: "artist \(index)")
                try artist.insert(database)
                return artist.id ?? 0
            }
        }
        let albumIds = try db.writer.write { database -> [Int64] in
            try (0..<albums).map { index in
                var album = Album(
                    title: "Album \(index)", sortTitle: "album \(index)",
                    artistId: artistIds[index % artistIds.count])
                try album.insert(database)
                return album.id ?? 0
            }
        }
        let codecs = ["flac", "alac", "wav", "dsf"]
        for batchStart in stride(from: 0, to: tracks, by: 500) {
            try db.writer.write { database in
                for i in batchStart..<min(batchStart + 500, tracks) {
                    var track = Track(
                        sourceId: source.id,
                        relativePath: "gen/\(i).flac",
                        title: "Track \(i % 997) \(i)",
                        artistId: artistIds[i % artistIds.count],
                        albumId: albumIds[i % albumIds.count],
                        duration: Double(i % 600),
                        codec: codecs[i % codecs.count],
                        sampleRate: 44_100)
                    try track.insert(database)
                }
            }
        }
    }
}
