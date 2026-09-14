import EscapementCore
import Foundation
import GRDB

/// Owns the SQLite connection pool (SPEC §5.1, §10):
/// WAL mode, concurrent reads, serialized writes.
public struct AppDatabase: Sendable {
    public let pool: DatabasePool

    /// Where the production database lives — also what the app shows when it
    /// cannot open it, so the owner can move the file aside by hand.
    public static var standardURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Escapement", isDirectory: true)
            .appendingPathComponent("library.sqlite")
    }

    /// Production database at ~/Library/Application Support/Escapement/library.sqlite.
    public static func standard() throws -> AppDatabase {
        let url = standardURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(path: url.path)
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
