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
}
