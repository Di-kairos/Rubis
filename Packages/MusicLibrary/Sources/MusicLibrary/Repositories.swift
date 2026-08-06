import EscapementCore
import Foundation
import GRDB

/// One row of FTS search output: track plus display names for grouping.
public struct SearchHit: Sendable, Equatable {
    public let track: Track
    public let artistName: String?
    public let albumTitle: String?
}

public struct TrackRepository: Sendable {
    private let db: any DatabaseAccess

    public init(db: any DatabaseAccess) {
        self.db = db
    }

    /// Batch upsert in one transaction (SPEC §5.2 — writes go in batches).
    public func insert(_ tracks: [Track]) throws -> [Track] {
        try db.writer.write { database in
            try tracks.map { track in
                var t = track
                try t.insert(database)
                return t
            }
        }
    }

    public func track(id: Int64) throws -> Track? {
        try db.reader.read { try Track.fetchOne($0, key: id) }
    }

    public func tracks(inAlbum albumId: Int64) throws -> [Track] {
        try db.reader.read {
            try Track
                .filter(Column("album_id") == albumId)
                .order(Column("disc_no").ascNullsLast, Column("track_no").ascNullsLast)
                .fetchAll($0)
        }
    }

    public func recentlyAdded(limit: Int = 100) throws -> [Track] {
        try db.reader.read {
            try Track.order(Column("added_at").desc).limit(limit).fetchAll($0)
        }
    }

    /// Треки по списку id с сохранением порядка запроса (порядок в плейлисте).
    /// Отсутствующие id молча выпадают.
    public func tracks(ids: [Int64]) throws -> [Track] {
        guard !ids.isEmpty else { return [] }
        let fetched = try db.reader.read { try Track.fetchAll($0, keys: ids) }
        let byId = Dictionary(
            uniqueKeysWithValues: fetched.compactMap { t in t.id.map { ($0, t) } })
        return ids.compactMap { byId[$0] }
    }

    public func delete(ids: [Int64]) throws {
        _ = try db.writer.write { try Track.deleteAll($0, keys: ids) }
    }

    public func count() throws -> Int {
        try db.reader.read { try Track.fetchCount($0) }
    }

    /// Сколько треков помечено недоступными (файл не найден при скане).
    public func unavailableCount() throws -> Int {
        try db.reader.read { try Track.filter(Column("unavailable") == true).fetchCount($0) }
    }

    /// FTS5 prefix search (SPEC §7.2). Query is sanitized into quoted prefix
    /// terms so user input can never break MATCH syntax.
    public func search(_ query: String, limit: Int = 50) throws -> [SearchHit] {
        let terms =
            query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }
        guard !terms.isEmpty else { return [] }
        let match = terms.joined(separator: " ")
        return try db.reader.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT track.*, artist.name AS artist_name, album.title AS album_title
                    FROM track_fts
                    JOIN track ON track.id = track_fts.rowid
                    LEFT JOIN artist ON artist.id = track.artist_id
                    LEFT JOIN album ON album.id = track.album_id
                    WHERE track_fts MATCH ?
                    ORDER BY rank
                    LIMIT ?
                    """,
                arguments: [match, limit])
            return try rows.map { row in
                SearchHit(
                    track: try Track(row: row),
                    artistName: row["artist_name"],
                    albumTitle: row["album_title"])
            }
        }
    }
}

public struct ArtistRepository: Sendable {
    private let db: any DatabaseAccess

    public init(db: any DatabaseAccess) {
        self.db = db
    }

    /// Fetches by sort name or inserts — scanner's dedup point (UNIQUE(sort_name)).
    public func findOrCreate(name: String) throws -> Artist {
        let sortName = Normalize.sortName(for: name)
        return try db.writer.write { database in
            if let existing =
                try Artist
                .filter(Column("sort_name") == sortName)
                .fetchOne(database)
            {
                return existing
            }
            var artist = Artist(name: name, sortName: sortName)
            try artist.insert(database)
            return artist
        }
    }

    public func all() throws -> [Artist] {
        try db.reader.read { try Artist.order(Column("sort_name")).fetchAll($0) }
    }
}

public struct AlbumRepository: Sendable {
    private let db: any DatabaseAccess

    public init(db: any DatabaseAccess) {
        self.db = db
    }

    public func insert(_ album: Album) throws -> Album {
        try db.writer.write { database in
            var a = album
            try a.insert(database)
            return a
        }
    }

    public func all() throws -> [Album] {
        try db.reader.read { try Album.order(Column("sort_title")).fetchAll($0) }
    }

    public func albums(byArtist artistId: Int64) throws -> [Album] {
        try db.reader.read {
            try Album
                .filter(Column("artist_id") == artistId)
                .order(Column("year").ascNullsLast)
                .fetchAll($0)
        }
    }

    /// Альбомы по свежести добавления треков (раздел Recently Added).
    public func recentlyAdded(limit: Int = 60) throws -> [Album] {
        try db.reader.read {
            try Album.fetchAll(
                $0,
                sql: """
                    SELECT album.* FROM album
                    JOIN track ON track.album_id = album.id
                    GROUP BY album.id
                    ORDER BY max(track.added_at) DESC
                    LIMIT ?
                    """,
                arguments: [limit])
        }
    }
}

public struct PlaylistRepository: Sendable {
    private let db: any DatabaseAccess

    public init(db: any DatabaseAccess) {
        self.db = db
    }

    public func create(name: String) throws -> Playlist {
        try db.writer.write { database in
            var playlist = Playlist(name: name)
            try playlist.insert(database)
            return playlist
        }
    }

    public func all() throws -> [Playlist] {
        try db.reader.read { try Playlist.order(Column("name")).fetchAll($0) }
    }

    /// Replaces the item list atomically — reordering is a full rewrite,
    /// positions stay dense 0..<n.
    public func setTracks(_ trackIds: [Int64], in playlistId: Int64) throws {
        try db.writer.write { database in
            try PlaylistItem
                .filter(Column("playlist_id") == playlistId)
                .deleteAll(database)
            for (position, trackId) in trackIds.enumerated() {
                try PlaylistItem(playlistId: playlistId, trackId: trackId, position: position)
                    .insert(database)
            }
            try database.execute(
                sql: "UPDATE playlist SET updated_at = ? WHERE id = ?",
                arguments: [Date(), playlistId])
        }
    }

    /// Дописывает треки в конец, пропуская уже присутствующие (d&d из библиотеки).
    public func append(_ ids: [Int64], to playlistId: Int64) throws {
        try db.writer.write { database in
            let existing = try Int64.fetchAll(
                database,
                sql: "SELECT track_id FROM playlist_item WHERE playlist_id = ?",
                arguments: [playlistId])
            var position = existing.count
            for id in ids where !existing.contains(id) {
                try PlaylistItem(playlistId: playlistId, trackId: id, position: position)
                    .insert(database)
                position += 1
            }
            try database.execute(
                sql: "UPDATE playlist SET updated_at = ? WHERE id = ?",
                arguments: [Date(), playlistId])
        }
    }

    public func rename(id: Int64, to name: String) throws {
        try db.writer.write { database in
            try database.execute(
                sql: "UPDATE playlist SET name = ?, updated_at = ? WHERE id = ?",
                arguments: [name, Date(), id])
        }
    }

    public func trackIds(in playlistId: Int64) throws -> [Int64] {
        try db.reader.read {
            try Int64.fetchAll(
                $0,
                sql: "SELECT track_id FROM playlist_item WHERE playlist_id = ? ORDER BY position",
                arguments: [playlistId])
        }
    }

    public func delete(id: Int64) throws {
        _ = try db.writer.write { try Playlist.deleteAll($0, keys: [id]) }
    }
}

public struct SourceRepository: Sendable {
    private let db: any DatabaseAccess

    public init(db: any DatabaseAccess) {
        self.db = db
    }

    public func upsert(_ source: Source) throws {
        try db.writer.write { try source.save($0) }
    }

    public func all() throws -> [Source] {
        try db.reader.read { try Source.order(Column("display_name")).fetchAll($0) }
    }

    public func delete(id: String) throws {
        _ = try db.writer.write { try Source.deleteAll($0, keys: [id]) }
    }
}
