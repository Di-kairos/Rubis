import EscapementCore
import Foundation
import GRDB

/// GRDB conformances for the Core domain models.
/// Column names are snake_case (SPEC §5.1); Swift properties are camelCase.

extension Source: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static let databaseTableName = "source"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy
        .convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy
        .convertToSnakeCase
}

extension Artist: @retroactive FetchableRecord, @retroactive MutablePersistableRecord {
    public static let databaseTableName = "artist"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy
        .convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy
        .convertToSnakeCase

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Album: @retroactive FetchableRecord, @retroactive MutablePersistableRecord {
    public static let databaseTableName = "album"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy
        .convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy
        .convertToSnakeCase

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Track: @retroactive FetchableRecord, @retroactive MutablePersistableRecord {
    public static let databaseTableName = "track"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy
        .convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy
        .convertToSnakeCase

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Playlist: @retroactive FetchableRecord, @retroactive MutablePersistableRecord {
    public static let databaseTableName = "playlist"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy
        .convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy
        .convertToSnakeCase

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension PlaylistItem: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static let databaseTableName = "playlist_item"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy
        .convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy
        .convertToSnakeCase
}

extension PlayHistoryEntry: @retroactive FetchableRecord, @retroactive MutablePersistableRecord {
    public static let databaseTableName = "play_history"
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy
        .convertFromSnakeCase
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy
        .convertToSnakeCase

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
