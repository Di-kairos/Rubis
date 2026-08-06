import EscapementCore
import Foundation
import GRDB

/// Scan progress for the sidebar strip (SPEC §5.2 — no modal windows).
public enum ScanProgress: Sendable {
    case enumerating(found: Int)
    case reading(done: Int, total: Int)
    case finished(ScanSummary)
}

public struct ScanSummary: Sendable, Equatable {
    public var added = 0
    public var updated = 0
    public var removed = 0
    public var unchanged = 0
    /// Paths that failed to read — the Problem files list.
    public var failed: [String] = []
}

/// Local-folder scanner (SPEC §5.2): security-scoped bookmarks, mtime+size
/// incrementality, parallel metadata reads, batched single-writer commits.
public actor LibraryScanner {
    public static let audioExtensions: Set<String> = [
        "flac", "m4a", "wav", "aiff", "aif", "dsf", "dff",
        "opus", "ogg", "mp3", "aac", "wv", "ape",
    ]
    static let batchSize = 500

    private let db: any DatabaseAccess
    private let covers: CoverCache
    private let logURL: URL

    /// Кэши разрешённых артистов/альбомов на время одного скана.
    private var artistCache: [String: Int64] = [:]
    private var albumCache: [String: Int64] = [:]

    public init(db: any DatabaseAccess, covers: CoverCache, logURL: URL? = nil) {
        self.db = db
        self.covers = covers
        self.logURL =
            logURL
            ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Escapement/scan.log")
    }

    // MARK: - Bookmarks (SPEC §5.2)

    public static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolveBookmark(_ data: Data) throws -> URL {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data, options: [.withSecurityScope],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        return url
    }

    // MARK: - Scan

    /// Полный/инкрементальный скан источника. Прогресс — колбэком; для UI
    /// есть обёртка scanStream(source:).
    @discardableResult
    public func scan(
        source: Source,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> ScanSummary {
        guard let bookmark = source.bookmark else {
            throw PlaybackError.fileNotFound("source \(source.displayName) has no bookmark")
        }
        let rootURL = try Self.resolveBookmark(bookmark)
        let accessing = rootURL.startAccessingSecurityScopedResource()
        defer { if accessing { rootURL.stopAccessingSecurityScopedResource() } }

        artistCache.removeAll()
        albumCache.removeAll()
        var summary = ScanSummary()

        // 1. Обход дерева
        var onDisk: [String: (url: URL, size: Int64, mtime: Date)] = [:]
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: rootURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else {
            throw PlaybackError.fileNotFound(rootURL.path)
        }
        while let next = enumerator.nextObject() {
            guard let url = next as? URL else { continue }
            guard Self.audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(rootURL.path.count).drop(while: { $0 == "/" }))
            onDisk[relative] = (
                url, Int64(values?.fileSize ?? 0), values?.contentModificationDate ?? .distantPast
            )
            if onDisk.count % 1000 == 0 {
                onProgress?(.enumerating(found: onDisk.count))
            }
        }
        onProgress?(.enumerating(found: onDisk.count))

        // 2. Что уже в базе
        struct KnownTrack: Codable, FetchableRecord {
            var id: Int64
            var relativePath: String
            var fileSize: Int64?
            var modifiedAt: Date?

            static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy
                .convertFromSnakeCase
        }
        let known: [String: KnownTrack] = try await db.reader.read { database in
            let rows = try KnownTrack.fetchAll(
                database,
                sql:
                    "SELECT id, relative_path, file_size, modified_at FROM track WHERE source_id = ?",
                arguments: [source.id])
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.relativePath, $0) })
        }

        // 3. Инкрементальность: только новые и изменённые (mtime или size)
        var toRead: [(relative: String, url: URL, existingID: Int64?)] = []
        for (relative, info) in onDisk {
            if let existing = known[relative] {
                let sameSize = existing.fileSize == info.size
                let sameTime =
                    existing.modifiedAt.map {
                        abs($0.timeIntervalSince(info.mtime)) < 1.0
                    } ?? false
                if sameSize && sameTime {
                    summary.unchanged += 1
                    continue
                }
                toRead.append((relative, info.url, existing.id))
            } else {
                toRead.append((relative, info.url, nil))
            }
        }

        // 4. Удалённые с диска
        let deletedIDs = known.filter { onDisk[$0.key] == nil }.map(\.value.id)
        if !deletedIDs.isEmpty {
            _ = try await db.writer.write { try Track.deleteAll($0, keys: deletedIDs) }
            summary.removed = deletedIDs.count
        }

        // 5. Параллельное чтение метаданных + батчевая запись
        let total = toRead.count
        var done = 0
        var batch: [(relative: String, existingID: Int64?, meta: FileMetadata)] = []

        try await withThrowingTaskGroup(
            of: (String, Int64?, Result<FileMetadata, Error>).self
        ) { group in
            var nextIndex = 0
            let width = ProcessInfo.processInfo.activeProcessorCount
            var inFlight = 0

            func addNext() {
                guard nextIndex < toRead.count else { return }
                let item = toRead[nextIndex]
                nextIndex += 1
                inFlight += 1
                group.addTask {
                    let result = Result { try MetadataReader.read(url: item.url) }
                    return (item.relative, item.existingID, result)
                }
            }
            for _ in 0..<width { addNext() }

            while inFlight > 0 {
                guard let (relative, existingID, result) = try await group.next() else { break }
                inFlight -= 1
                addNext()
                done += 1
                if done % 50 == 0 || done == total {
                    onProgress?(.reading(done: done, total: total))
                }
                switch result {
                case .success(let meta):
                    batch.append((relative, existingID, meta))
                    if batch.count >= Self.batchSize {
                        try await commit(batch: batch, source: source, summary: &summary)
                        batch.removeAll(keepingCapacity: true)
                    }
                case .failure(let error):
                    summary.failed.append(relative)
                    log("problem file: \(relative) — \(error)")
                }
            }
        }
        if !batch.isEmpty {
            try await commit(batch: batch, source: source, summary: &summary)
        }

        try await db.writer.write { database in
            try database.execute(
                sql: "UPDATE source SET last_scan_at = ? WHERE id = ?",
                arguments: [Date(), source.id])
        }
        log(
            "scan \(source.displayName): +\(summary.added) ~\(summary.updated) -\(summary.removed) =\(summary.unchanged) !\(summary.failed.count)"
        )
        onProgress?(.finished(summary))
        return summary
    }

    /// AsyncStream-обёртка для UI (TASKS фазы 4).
    public nonisolated func scanStream(source: Source) -> AsyncThrowingStream<ScanProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await self.scan(source: source) { progress in
                        continuation.yield(progress)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Запись батча (одна транзакция, SPEC §5.2)

    private func commit(
        batch: [(relative: String, existingID: Int64?, meta: FileMetadata)],
        source: Source,
        summary: inout ScanSummary
    ) async throws {
        // Снимки кэшей внутрь Sendable-замыкания, результат — наружу.
        let artistsSnapshot = artistCache
        let albumsSnapshot = albumCache
        let coverCache = covers
        let batchValues = batch.map { item in
            (item.relative, item.existingID, item.meta, onDiskValues(for: item, source: source))
        }

        let result: (added: Int, updated: Int, artists: [String: Int64], albums: [String: Int64]) =
            try await db.writer.write { database in
                var artists = artistsSnapshot
                var albums = albumsSnapshot
                var added = 0
                var updated = 0
                for (relative, existingID, meta, diskValues) in batchValues {
                    let item = (relative: relative, existingID: existingID, meta: meta)
                    let values = diskValues
                    let meta = item.meta

                    // Артист трека
                    let trackArtistID = try Self.resolveArtist(
                        name: meta.artist, sortTag: meta.artistSortTag,
                        cache: &artists, database: database)

                    // Album artist по правилам §5.3
                    let albumArtistName =
                        meta.albumArtistTag
                        ?? (meta.isCompilationTagged ? "Various Artists" : meta.artist)
                    let albumArtistID = try Self.resolveArtist(
                        name: albumArtistName, sortTag: meta.albumSortTag == nil ? nil : nil,
                        cache: &artists, database: database)

                    // Альбом
                    var albumID: Int64?
                    if let albumTitle = meta.albumTitle {
                        let key = "\(albumArtistName ?? "")\u{1F}\(albumTitle)"
                        if let cached = albums[key] {
                            albumID = cached
                        } else {
                            let sortTitle = meta.albumSortTag ?? Normalize.sortName(for: albumTitle)
                            var album =
                                try Album
                                .filter(Column("sort_title") == sortTitle)
                                .filter(Column("artist_id") == albumArtistID)
                                .fetchOne(database)
                            if album == nil {
                                var new = Album(
                                    title: albumTitle, sortTitle: sortTitle,
                                    artistId: albumArtistID,
                                    albumArtist: albumArtistName, year: meta.year, date: meta.date,
                                    discCount: nil, isCompilation: meta.isCompilationTagged)
                                if let cover = meta.embeddedCover,
                                    let hash = try? coverCache.store(cover)
                                {
                                    new.coverHash = hash
                                }
                                try new.insert(database)
                                album = new
                            }
                            albumID = album?.id
                            if let id = album?.id { albums[key] = id }
                        }
                    }

                    var track = Track(
                        id: item.existingID,
                        sourceId: source.id,
                        relativePath: item.relative,
                        fileSize: values.size,
                        modifiedAt: values.mtime,
                        title: meta.title,
                        artistId: trackArtistID,
                        albumId: albumID,
                        trackNo: meta.trackNo,
                        discNo: meta.discNo,
                        duration: meta.duration,
                        codec: meta.codec,
                        sampleRate: meta.sampleRate,
                        bitDepth: meta.bitDepth,
                        channels: meta.channels,
                        bitrate: meta.bitrate,
                        replaygainTrack: meta.replaygainTrack,
                        replaygainAlbum: meta.replaygainAlbum)
                    if item.existingID != nil {
                        try track.update(database)
                        updated += 1
                    } else {
                        try track.insert(database)
                        added += 1
                    }
                }
                return (added, updated, artists, albums)
            }
        artistCache = result.artists
        albumCache = result.albums
        summary.added += result.added
        summary.updated += result.updated
    }

    /// mtime/size для записи в БД — повторный stat дешевле таскания через TaskGroup.
    private func onDiskValues(
        for item: (relative: String, existingID: Int64?, meta: FileMetadata), source: Source
    ) -> (size: Int64?, mtime: Date?) {
        guard let bookmark = source.bookmark,
            let root = try? Self.resolveBookmark(bookmark)
        else { return (nil, nil) }
        let url = root.appendingPathComponent(item.relative)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return (values?.fileSize.map(Int64.init), values?.contentModificationDate)
    }

    private static func resolveArtist(
        name: String?, sortTag: String?,
        cache: inout [String: Int64], database: Database
    ) throws -> Int64? {
        guard let name, !name.isEmpty else { return nil }
        let sortName = sortTag ?? Normalize.sortName(for: name)
        if let cached = cache[sortName] { return cached }
        if let existing = try Artist.filter(Column("sort_name") == sortName).fetchOne(database) {
            cache[sortName] = existing.id
            return existing.id
        }
        var artist = Artist(name: name, sortName: sortName)
        try artist.insert(database)
        cache[sortName] = artist.id
        return artist.id
    }

    // MARK: -

    private func log(_ message: String) {
        Log.library.info("\(message, privacy: .public)")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            try? FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
