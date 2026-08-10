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
    /// Файл узнан под новым путём (size+mtime) — id, плейлисты и история целы.
    public var moved = 0
    /// Файлов не найдено — треки помечены недоступными, а не удалены.
    public var unavailable = 0
    /// Файл вернулся на место — пометка снята.
    public var restored = 0
    /// Недоступные двойники, снятые после переезда файла в другой источник.
    public var deduplicated = 0
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
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]
    /// Имена файлов обложки в порядке убывания важности: front.jpg побеждает back.jpg.
    static let artFilters = ["front", "cover", "folder", "album"]
    static let batchSize = 500

    private let db: any DatabaseAccess
    private let covers: CoverCache
    private let logURL: URL

    /// Кэши разрешённых артистов/альбомов на время одного скана.
    private var artistCache: [String: Int64] = [:]
    private var albumCache: [String: Int64] = [:]
    /// Обложки из папок на время скана: путь директории → байты картинки.
    private var folderArtCache: [String: Data?] = [:]

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

    public static func resolveBookmark(_ data: Data) throws -> URL {
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
        folderArtCache.removeAll()
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
            var unavailable: Bool

            static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy
                .convertFromSnakeCase
        }
        let known: [String: KnownTrack] = try await db.reader.read { database in
            let rows = try KnownTrack.fetchAll(
                database,
                sql: """
                    SELECT id, relative_path, file_size, modified_at, unavailable
                    FROM track WHERE source_id = ?
                    """,
                arguments: [source.id])
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.relativePath, $0) })
        }

        // 3. Инкрементальность: только новые и изменённые (mtime или size)
        var toRead: [(relative: String, url: URL, existingID: Int64?)] = []
        /// Вернувшиеся файлы — снять пометку недоступности.
        var restoredIDs: [Int64] = []
        for (relative, info) in onDisk {
            if let existing = known[relative] {
                let sameSize = existing.fileSize == info.size
                let sameTime =
                    existing.modifiedAt.map {
                        abs($0.timeIntervalSince(info.mtime)) < 1.0
                    } ?? false
                if sameSize && sameTime {
                    summary.unchanged += 1
                    if existing.unavailable { restoredIDs.append(existing.id) }
                    continue
                }
                toRead.append((relative, info.url, existing.id))
            } else {
                toRead.append((relative, info.url, nil))
            }
        }

        // 4. Пропавшие пути: сначала ищем перенос — тот же size+mtime под новым
        //    именем. Узнали → трек сохраняет id (а с ним плейлисты и историю),
        //    просто меняет путь. Не узнали → помечаем недоступным, не удаляем:
        //    том мог быть отключён (D-002), файл может вернуться.
        var missing = known.filter { onDisk[$0.key] == nil }.map(\.value)
        if !missing.isEmpty {
            var newIndexBySignature: [String: Int] = [:]
            for (index, item) in toRead.enumerated() where item.existingID == nil {
                if let info = onDisk[item.relative] {
                    newIndexBySignature[Self.signature(size: info.size, mtime: info.mtime)] = index
                }
            }
            var stillMissing: [KnownTrack] = []
            for candidate in missing {
                guard let size = candidate.fileSize, let mtime = candidate.modifiedAt,
                    let index =
                        newIndexBySignature
                        .removeValue(forKey: Self.signature(size: size, mtime: mtime))
                else {
                    stillMissing.append(candidate)
                    continue
                }
                toRead[index].existingID = candidate.id
                summary.moved += 1
            }
            missing = stillMissing
        }

        // 4b. Файл мог переехать в ДРУГОЙ источник — так бывает, когда папки
        //     источников разложены по направлениям музыки. В базе он висит
        //     недоступным под старым источником; узнаём по той же подписи и
        //     забираем строку себе: id, плейлисты и история переживают переезд,
        //     призрак в прежнем источнике не остаётся.
        let arrivals: [(index: Int, signature: String)] = toRead.enumerated()
            .compactMap { index, item in
                guard item.existingID == nil, let info = onDisk[item.relative] else { return nil }
                return (index, Self.signature(size: info.size, mtime: info.mtime))
            }
        if !arrivals.isEmpty {
            let orphans: [KnownTrack] = try await db.reader.read { database in
                try KnownTrack.fetchAll(
                    database,
                    sql: """
                        SELECT id, relative_path, file_size, modified_at, unavailable
                        FROM track WHERE unavailable = 1 AND source_id <> ?
                        """,
                    arguments: [source.id])
            }
            var orphanBySignature: [String: Int64] = [:]
            for orphan in orphans {
                guard let size = orphan.fileSize, let mtime = orphan.modifiedAt else { continue }
                orphanBySignature[Self.signature(size: size, mtime: mtime)] = orphan.id
            }
            for arrival in arrivals {
                guard let id = orphanBySignature.removeValue(forKey: arrival.signature) else {
                    continue
                }
                toRead[arrival.index].existingID = id
                summary.moved += 1
            }
        }

        if !missing.isEmpty {
            let ids = missing.map(\.id)
            try await db.writer.write { database in
                try database.execute(
                    sql: """
                        UPDATE track SET unavailable = 1
                        WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ",")))
                        """,
                    arguments: StatementArguments(ids))
            }
            summary.unavailable = ids.count
        }
        let restored = restoredIDs
        if !restored.isEmpty {
            try await db.writer.write { database in
                try database.execute(
                    sql: """
                        UPDATE track SET unavailable = 0
                        WHERE id IN (\(restored.map { _ in "?" }.joined(separator: ",")))
                        """,
                    arguments: StatementArguments(restored))
            }
            summary.restored = restored.count
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

        // 6. Уборка двойников. Пункт 4b ловит переезд, только когда старый
        //    источник просканирован раньше нового. При обратном порядке файл
        //    успевает войти новой строкой, а старая остаётся недоступной —
        //    два трека на один файл. Совпали подпись и разные источники,
        //    причём живой экземпляр найден → недоступный больше не нужен.
        summary.deduplicated = try await db.writer.write { database -> Int in
            try database.execute(
                sql: """
                    DELETE FROM track
                    WHERE unavailable = 1
                      AND file_size IS NOT NULL AND modified_at IS NOT NULL
                      AND EXISTS (
                        SELECT 1 FROM track other
                        WHERE other.unavailable = 0
                          AND other.source_id <> track.source_id
                          AND other.file_size = track.file_size
                          AND other.modified_at = track.modified_at)
                    """)
            return database.changesCount
        }

        try await db.writer.write { database in
            try database.execute(
                sql: "UPDATE source SET last_scan_at = ? WHERE id = ?",
                arguments: [Date(), source.id])
        }
        log(
            "scan \(source.displayName): +\(summary.added) ~\(summary.updated) →\(summary.moved) ?\(summary.unavailable) ↩\(summary.restored) ×\(summary.deduplicated) =\(summary.unchanged) !\(summary.failed.count)"
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
            (
                item.relative, item.existingID, item.meta,
                onDiskValues(for: item, source: source),
                item.meta.embeddedCover == nil
                    ? folderArt(for: item.relative, source: source) : nil
            )
        }

        let result: (added: Int, updated: Int, artists: [String: Int64], albums: [String: Int64]) =
            try await db.writer.write { database in
                var artists = artistsSnapshot
                var albums = albumsSnapshot
                var added = 0
                var updated = 0
                for (relative, existingID, meta, diskValues, folderCover) in batchValues {
                    let item = (relative: relative, existingID: existingID, meta: meta)
                    let values = diskValues
                    let meta = item.meta
                    // Тег важнее файла в папке (SPEC §5.4).
                    let cover = meta.embeddedCover ?? folderCover

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
                                if let cover, let hash = try? coverCache.store(cover) {
                                    new.coverHash = hash
                                }
                                try new.insert(database)
                                album = new
                            } else if album?.coverHash == nil, let cover,
                                let hash = try? coverCache.store(cover)
                            {
                                // Альбом уже был без обложки — досыпаем найденную.
                                album?.coverHash = hash
                                try album?.update(database)
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

    /// Подпись содержимого файла для распознавания переноса: размер + mtime
    /// с точностью до секунды (mv сохраняет оба).
    /// ponytail: без хеша содержимого — коллизия «два файла одного размера и
    /// времени» даёт неверную привязку id; переходить на хеш, если всплывёт.
    private static func signature(size: Int64, mtime: Date) -> String {
        "\(size)-\(Int(mtime.timeIntervalSince1970.rounded()))"
    }

    /// Обложка из папки трека, кэш на директорию (тег важнее, зовётся только
    /// когда встроенной картинки нет).
    private func folderArt(for relative: String, source: Source) -> Data? {
        guard let bookmark = source.bookmark,
            let root = try? Self.resolveBookmark(bookmark)
        else { return nil }
        let directory = root.appendingPathComponent(relative).deletingLastPathComponent()
        if let cached = folderArtCache[directory.path] { return cached }
        let data = Self.folderArt(in: directory)
        folderArtCache[directory.path] = data
        return data
    }

    /// Выбор картинки в директории: фильтры имён по важности, среди совпавших —
    /// самый большой файл. Совпадений нет — самая большая из всех.
    static func folderArt(in directory: URL) -> Data? {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles])
        else { return nil }
        let images = entries.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        guard !images.isEmpty else { return nil }

        var candidates: [URL] = []
        for filter in artFilters {
            candidates = images.filter {
                $0.deletingPathExtension().lastPathComponent.lowercased().contains(filter)
            }
            if !candidates.isEmpty { break }
        }
        if candidates.isEmpty { candidates = images }

        let biggest = candidates.max { left, right in
            let leftSize = (try? left.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let rightSize = (try? right.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return leftSize < rightSize
        }
        return biggest.flatMap { try? Data(contentsOf: $0) }
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
