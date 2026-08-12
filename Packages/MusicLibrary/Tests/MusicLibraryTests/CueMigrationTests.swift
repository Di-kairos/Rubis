import Foundation
import GRDB
import Testing

@testable import EscapementCore
@testable import MusicLibrary

struct CueMigrationTests {

    @Test func cueColumnsSurviveTheRebuild() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue)
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO source (id, kind, display_name) VALUES ('s', 'folder', 'S')")
        }
        var first = Track(
            sourceId: "s", relativePath: "album.flac", title: "One", duration: 100,
            codec: "flac", sampleRate: 44100, cueStart: 0, cueEnd: 100)
        var second = Track(
            sourceId: "s", relativePath: "album.flac", title: "Two", duration: 80,
            codec: "flac", sampleRate: 44100, cueStart: 100, cueEnd: nil)
        try queue.write { db in
            try first.insert(db)
            try second.insert(db)
        }
        let loaded = try queue.read { try Track.order(Column("cue_start")).fetchAll($0) }
        #expect(loaded.count == 2)
        #expect(loaded[0].cueEnd == 100)
        #expect(loaded[1].isCueSegment)
        #expect(loaded[1].cueEnd == nil)
    }

    @Test func plainTracksStillCannotShareAPath() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue)
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO source (id, kind, display_name) VALUES ('s', 'folder', 'S')")
        }
        var track = Track(
            sourceId: "s", relativePath: "one.flac", title: "One", duration: 1, codec: "flac",
            sampleRate: 44100)
        try queue.write { try track.insert($0) }
        var twin = Track(
            sourceId: "s", relativePath: "one.flac", title: "Twin", duration: 1, codec: "flac",
            sampleRate: 44100)
        #expect(throws: DatabaseError.self) {
            try queue.write { try twin.insert($0) }
        }
    }

    @Test func searchIndexKeepsWorkingAfterTheRebuild() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue)
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO source (id, kind, display_name) VALUES ('s', 'folder', 'S')")
        }
        var track = Track(
            sourceId: "s", relativePath: "a.flac", title: "Blue in Green", duration: 1,
            codec: "flac", sampleRate: 44100)
        try queue.write { try track.insert($0) }
        let hits = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM track_fts WHERE track_fts MATCH 'blue'")
        }
        #expect(hits == 1)
    }

    @Test func anExistingLibrarySurvivesTheRebuild() throws {
        // Главный риск перестройки: у владельца в базе уже есть треки,
        // плейлисты и история, и они ссылаются на track(id).
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue, upTo: "v2_track_unavailable")
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO source (id, kind, display_name) VALUES ('s', 'folder', 'S');
                    INSERT INTO track (id, source_id, relative_path, title, duration, codec,
                                       sample_rate, channels, added_at)
                    VALUES (7, 's', 'one.flac', 'So What', 545.0, 'flac', 44100, 2, '2026-01-01');
                    INSERT INTO playlist (id, name, created_at, updated_at)
                    VALUES (1, 'Evening', '2026-01-01', '2026-01-01');
                    INSERT INTO playlist_item (playlist_id, track_id, position) VALUES (1, 7, 0);
                    INSERT INTO play_history (track_id, played_at, completed, duration_played)
                    VALUES (7, '2026-01-02', 1, 545.0);
                    """)
        }

        try Migrations.migrator.migrate(queue)

        try queue.read { db in
            let track = try #require(try Track.fetchOne(db, key: 7))
            #expect(track.title == "So What")
            #expect(track.cueStart == nil)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM playlist_item") == 1)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM play_history") == 1)
            // Индекс поиска строится триггерами: строка 7 попала в него
            // до перестройки и должна пережить её.
            #expect(
                try Int.fetchOne(
                    db, sql: "SELECT count(*) FROM track_fts WHERE track_fts MATCH 'what'") == 1)
        }
    }
}
