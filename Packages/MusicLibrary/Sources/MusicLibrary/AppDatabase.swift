import EscapementCore
import Foundation
import GRDB

/// Owns the SQLite connection pool (SPEC §5.1, §10):
/// WAL mode, concurrent reads, serialized writes.
public struct AppDatabase: Sendable {
    public let pool: DatabasePool

    /// Production database at ~/Library/Application Support/Escapement/library.sqlite.
    public static func standard() throws -> AppDatabase {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
            0
        ]
        .appendingPathComponent("Escapement", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try AppDatabase(path: dir.appendingPathComponent("library.sqlite").path)
    }

    /// On-disk database at an explicit path. WAL is on by default for DatabasePool.
    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        pool = try DatabasePool(path: path, configuration: config)
        try Migrations.migrator.migrate(pool)
    }

    /// In-memory database for tests. DatabaseQueue-backed (in-memory pools
    /// don't share state across connections), wrapped in the same API.
    public static func inMemory() throws -> TestDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        try Migrations.migrator.migrate(queue)
        return TestDatabase(queue: queue)
    }
}

/// Test-only wrapper exposing the same reader/writer as AppDatabase.
public struct TestDatabase: Sendable {
    public let queue: DatabaseQueue
}

/// Unified access for repositories: production pool or test queue.
public protocol DatabaseAccess: Sendable {
    var reader: any DatabaseReader { get }
    var writer: any DatabaseWriter { get }
}

extension AppDatabase: DatabaseAccess {
    public var reader: any DatabaseReader { pool }
    public var writer: any DatabaseWriter { pool }
}

extension TestDatabase: DatabaseAccess {
    public var reader: any DatabaseReader { queue }
    public var writer: any DatabaseWriter { queue }
}
