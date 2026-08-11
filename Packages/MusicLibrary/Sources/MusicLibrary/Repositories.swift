import EscapementCore
import Foundation
import GRDB

/// Track plus display names — строка списка и результат поиска.
public struct SearchHit: Sendable, Equatable, Identifiable {
    public let track: Track
    public let artistName: String?
    public let albumTitle: String?

    /// Строки всегда приходят из БД, где id есть; -1 — недостижимая заглушка.
    public var id: Int64 { track.id ?? -1 }

    public init(track: Track, artistName: String?, albumTitle: String?) {
        self.track = track
        self.artistName = artistName
        self.albumTitle = albumTitle
    }
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

    /// Все треки артиста по альбомам — Enter на строке артиста в поиске.
    public func tracks(byArtist artistId: Int64) throws -> [Track] {
        try db.reader.read {
            try Track
                .filter(Column("artist_id") == artistId)
                .order(
                    Column("album_id").ascNullsLast, Column("disc_no").ascNullsLast,
                    Column("track_no").ascNullsLast
                )
                .fetchAll($0)
        }
    }

    /// Серверные идентификаторы источника → id строк. Синхронизация каталога
    /// (фаза 6) узнаёт свои треки только по `remote_id`: путей у сервера нет.
    public func remoteIds(inSource sourceId: String) throws -> [String: Int64] {
        try db.reader.read { database in
            let rows = try Row.fetchAll(
                database,
                sql:
                    "SELECT id, remote_id FROM track WHERE source_id = ? AND remote_id IS NOT NULL",
                arguments: [sourceId])
            return Dictionary(
                rows.compactMap { row -> (String, Int64)? in
                    guard let remote: String = row["remote_id"], let id: Int64 = row["id"]
                    else { return nil }
                    return (remote, id)
                }, uniquingKeysWith: { first, _ in first })
        }
    }

    public func recentlyAdded(limit: Int = 100) throws -> [Track] {
        try db.reader.read {
            try Track.order(Column("added_at").desc).limit(limit).fetchAll($0)
        }
    }

    /// Вся библиотека с именами артиста и альбома — колонки раздела Tracks.
    /// Без ORDER BY: порядок всё равно задаёт `TrackSort` в UI.
    public func allWithNames() throws -> [SearchHit] {
        try db.reader.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT track.*, artist.name AS artist_name, album.title AS album_title
                    FROM track
                    LEFT JOIN artist ON artist.id = track.artist_id
                    LEFT JOIN album ON album.id = track.album_id
                    """)
            return try Self.hits(from: rows)
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

    /// Разом помечает весь источник недоступным или снова доступным
    /// (сервер не отвечает — SPEC §6.3). Тот же флаг, что у пропавших файлов:
    /// приглушение в списках, значок и выпадение из очереди уже написаны
    /// под него. Возвращает число изменённых строк — нулевое означает,
    /// что состояние и так было таким, и экраны трогать незачем.
    @discardableResult
    public func setUnavailable(_ flag: Bool, inSource sourceId: String) throws -> Int {
        try db.writer.write { database in
            try database.execute(
                sql: """
                    UPDATE track SET unavailable = ?
                    WHERE source_id = ? AND unavailable IS NOT ?
                    """,
                arguments: [flag, sourceId, flag])
            return database.changesCount
        }
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
            return try Self.hits(from: rows)
        }
    }

    private static func hits(from rows: [Row]) throws -> [SearchHit] {
        try rows.map { row in
            SearchHit(
                track: try Track(row: row),
                artistName: row["artist_name"],
                albumTitle: row["album_title"])
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

    public func artist(id: Int64) throws -> Artist? {
        try db.reader.read { try Artist.fetchOne($0, key: id) }
    }

    /// Группа Artists в поиске (SPEC §7.2): префикс по нормализованному имени,
    /// поэтому «bjork» находит «Björk», а «beatles» — «The Beatles».
    public func search(_ query: String, limit: Int = 8) throws -> [Artist] {
        guard let range = PrefixRange(query) else { return [] }
        return try db.reader.read {
            try Artist
                .filter(Column("sort_name") >= range.low && Column("sort_name") < range.high)
                .order(Column("sort_name"))
                .limit(limit)
                .fetchAll($0)
        }
    }
}

/// Диапазон «строки, начинающиеся с префикса» для поиска по sort-ключу.
/// Range вместо `LIKE 'x%'`: с ESCAPE SQLite отключает LIKE-оптимизацию и
/// сканирует индекс целиком, а на сравнениях идёт seek по индексу.
/// Заодно `%` и `_` из запроса — обычные символы, а не шаблон.
struct PrefixRange {
    let low: String
    let high: String

    /// nil на пустом запросе — иначе диапазон накрыл бы всю таблицу.
    init?(_ query: String) {
        let normalized = Normalize.sortName(for: query)
        guard !normalized.isEmpty else { return nil }
        low = normalized
        // Верхняя граница: старший скаляр Unicode — больше него в ключе быть нечему.
        high = normalized + "\u{10FFFF}"
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

    public func album(id: Int64) throws -> Album? {
        try db.reader.read { try Album.fetchOne($0, key: id) }
    }

    /// Группа Albums в поиске (SPEC §7.2) — префикс по `sort_title`.
    public func search(_ query: String, limit: Int = 8) throws -> [Album] {
        guard let range = PrefixRange(query) else { return [] }
        return try db.reader.read {
            try Album
                .filter(Column("sort_title") >= range.low && Column("sort_title") < range.high)
                .order(Column("sort_title"))
                .limit(limit)
                .fetchAll($0)
        }
    }

    /// Альбом по тому же ключу, каким его находит сканер: нормализованное
    /// название плюс артист. Серверный каталог ложится в те же строки, что и
    /// локальный, — у альбома нет своего `remote_id` в схеме, и не нужно.
    public func findOrCreate(
        title: String, artistId: Int64?, albumArtist: String?, year: Int?
    ) throws -> Album {
        let sortTitle = Normalize.sortName(for: title)
        return try db.writer.write { database in
            if let existing =
                try Album
                .filter(Column("sort_title") == sortTitle)
                .filter(Column("artist_id") == artistId)
                .fetchOne(database)
            {
                return existing
            }
            var album = Album(
                title: title, sortTitle: sortTitle, artistId: artistId,
                albumArtist: albumArtist, year: year)
            try album.insert(database)
            return album
        }
    }

    /// Ставит альбому обложку, если её ещё нет. Найденная первой остаётся:
    /// у сканера папок то же правило (LibraryScanner), и серверная картинка
    /// не должна затирать вложенную в файлы.
    /// Возвращает `true`, если запись изменилась.
    @discardableResult
    public func setCoverHashIfMissing(_ hash: String, albumId: Int64) throws -> Bool {
        try db.writer.write { database in
            guard var album = try Album.fetchOne(database, key: albumId),
                album.coverHash == nil
            else { return false }
            album.coverHash = hash
            try album.update(database)
            return true
        }
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
