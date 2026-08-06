import Foundation
import GRDB

/// Schema migrations. v1_initial matches SPEC §5.1 verbatim.
/// Schema changes after Phase 2 require owner approval (CLAUDE.md).
enum Migrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.execute(
                sql: """
                    CREATE TABLE source (
                        id            TEXT PRIMARY KEY,
                        kind          TEXT NOT NULL,
                        display_name  TEXT NOT NULL,
                        bookmark      BLOB,
                        server_url    TEXT,
                        username      TEXT,
                        enabled       INTEGER NOT NULL DEFAULT 1,
                        last_scan_at  DATETIME
                    );

                    CREATE TABLE artist (
                        id          INTEGER PRIMARY KEY,
                        name        TEXT NOT NULL,
                        sort_name   TEXT NOT NULL,
                        mbid        TEXT,
                        UNIQUE(sort_name)
                    );

                    CREATE TABLE album (
                        id            INTEGER PRIMARY KEY,
                        title         TEXT NOT NULL,
                        sort_title    TEXT NOT NULL,
                        artist_id     INTEGER REFERENCES artist(id),
                        album_artist  TEXT,
                        year          INTEGER,
                        date          TEXT,
                        mbid          TEXT,
                        disc_count    INTEGER,
                        cover_hash    TEXT,
                        is_compilation INTEGER NOT NULL DEFAULT 0
                    );

                    CREATE TABLE track (
                        id             INTEGER PRIMARY KEY,
                        source_id      TEXT NOT NULL REFERENCES source(id) ON DELETE CASCADE,
                        remote_id      TEXT,
                        relative_path  TEXT,
                        file_size      INTEGER,
                        modified_at    DATETIME,
                        title          TEXT NOT NULL,
                        artist_id      INTEGER REFERENCES artist(id),
                        album_id       INTEGER REFERENCES album(id),
                        track_no       INTEGER,
                        disc_no        INTEGER,
                        duration       REAL NOT NULL,
                        codec          TEXT NOT NULL,
                        sample_rate    INTEGER NOT NULL,
                        bit_depth      INTEGER,
                        channels       INTEGER NOT NULL,
                        bitrate        INTEGER,
                        replaygain_track REAL,
                        replaygain_album REAL,
                        added_at       DATETIME NOT NULL,
                        UNIQUE(source_id, relative_path),
                        UNIQUE(source_id, remote_id)
                    );

                    CREATE TABLE playlist (
                        id          INTEGER PRIMARY KEY,
                        name        TEXT NOT NULL,
                        created_at  DATETIME NOT NULL,
                        updated_at  DATETIME NOT NULL,
                        is_smart    INTEGER NOT NULL DEFAULT 0,
                        rules_json  TEXT
                    );

                    CREATE TABLE playlist_item (
                        playlist_id INTEGER NOT NULL REFERENCES playlist(id) ON DELETE CASCADE,
                        track_id    INTEGER NOT NULL REFERENCES track(id) ON DELETE CASCADE,
                        position    INTEGER NOT NULL,
                        PRIMARY KEY (playlist_id, position)
                    );

                    CREATE TABLE play_history (
                        id          INTEGER PRIMARY KEY,
                        track_id    INTEGER NOT NULL REFERENCES track(id) ON DELETE CASCADE,
                        played_at   DATETIME NOT NULL,
                        completed   INTEGER NOT NULL,
                        duration_played REAL NOT NULL
                    );

                    CREATE INDEX idx_track_album ON track(album_id, disc_no, track_no);
                    CREATE INDEX idx_track_artist ON track(artist_id);
                    CREATE INDEX idx_track_added ON track(added_at DESC);
                    CREATE INDEX idx_album_sort ON album(sort_title);
                    CREATE INDEX idx_album_artist_year ON album(artist_id, year);
                    CREATE INDEX idx_history_played ON play_history(played_at DESC);
                    """)

            // Contentless FTS5 (SPEC §5.1). contentless_delete=1 lets the
            // UPDATE/DELETE triggers below remove rows by rowid — plain
            // contentless tables cannot do that (needs SQLite 3.43+, macOS 15 ships newer).
            try db.execute(
                sql: """
                    CREATE VIRTUAL TABLE track_fts USING fts5(
                        title, artist_name, album_title,
                        content='', contentless_delete=1,
                        tokenize='unicode61 remove_diacritics 2'
                    );
                    """)

            // track → track_fts sync. Artist/album names are denormalized into
            // the index at write time via subselects.
            try db.execute(
                sql: """
                    CREATE TRIGGER track_fts_insert AFTER INSERT ON track BEGIN
                        INSERT INTO track_fts(rowid, title, artist_name, album_title)
                        VALUES (
                            new.id,
                            new.title,
                            coalesce((SELECT name FROM artist WHERE id = new.artist_id), ''),
                            coalesce((SELECT title FROM album WHERE id = new.album_id), '')
                        );
                    END;

                    CREATE TRIGGER track_fts_delete AFTER DELETE ON track BEGIN
                        DELETE FROM track_fts WHERE rowid = old.id;
                    END;

                    CREATE TRIGGER track_fts_update AFTER UPDATE ON track BEGIN
                        DELETE FROM track_fts WHERE rowid = old.id;
                        INSERT INTO track_fts(rowid, title, artist_name, album_title)
                        VALUES (
                            new.id,
                            new.title,
                            coalesce((SELECT name FROM artist WHERE id = new.artist_id), ''),
                            coalesce((SELECT title FROM album WHERE id = new.album_id), '')
                        );
                    END;
                    """)
        }

        return migrator
    }
}
