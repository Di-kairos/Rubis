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

    /// Строка трека глазами скана: чего хватает, чтобы решить судьбу файла,
    /// не вычитывая всю таблицу.
    struct KnownTrack: Codable, FetchableRecord {
        var id: Int64
        var relativePath: String
        var fileSize: Int64?
        var modifiedAt: Date?
        var unavailable: Bool
        var cueStart: Double?

        static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy
            .convertFromSnakeCase
    }

    /// Лист и его дорожки, привязанные к аудиофайлу (D-013).
    struct CueContext: Sendable {
        var sheet: CueSheet
        var tracks: [CueSheet.Track]
    }

    /// Разбирает найденные `.cue` и раскладывает их по путям аудиофайлов.
    ///
    /// Один лист описывает один диск, но ссылаться может на несколько файлов
    /// (рип «дорожка в файл»): каждый FILE получает свои дорожки. Пути,
    /// которых нет на диске, отбрасываются здесь же — дальше по коду CUE уже
    /// означает «файл существует и режется».
    static func cueSegments(
        from cueURLs: [URL], root: URL,
        onDisk: [String: (url: URL, size: Int64, mtime: Date)]
    ) -> [String: CueContext] {
        var result: [String: CueContext] = [:]
        for cueURL in cueURLs {
            guard let sheet = (try? CueSheet.read(contentsOf: cueURL)) ?? nil else { continue }
            let directory = cueURL.deletingLastPathComponent()
            for file in sheet.files {
                let audioURL = directory.appendingPathComponent(file.name)
                let relative = String(
                    audioURL.path.dropFirst(root.path.count).drop(while: { $0 == "/" }))
                guard onDisk[relative] != nil, !file.tracks.isEmpty else { continue }
                // Файл на одну дорожку резать нечего: это обычный трек,
                // и лишняя строка cue_start только мешала бы переезду.
                guard file.tracks.count > 1 || file.tracks[0].start > 0 else { continue }
                result[relative] = CueContext(sheet: sheet, tracks: file.tracks)
            }
        }
        return result
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
        var cueURLs: [URL] = []
        while let next = enumerator.nextObject() {
            guard let url = next as? URL else { continue }
            let ext = url.pathExtension.lowercased()
            if ext == "cue" {
                cueURLs.append(url)
                continue
            }
            guard Self.audioExtensions.contains(ext) else { continue }
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

        // 1b. CUE-листы: рип диска одним файлом плюс границы дорожек (D-013).
        //     Лист, чей аудиофайл не найден, молча пропускается — рядом с
        //     .cue часто лежит ссылка на .wav, которого давно нет.
        let cues = Self.cueSegments(from: cueURLs, root: rootURL, onDisk: onDisk)

        // 2. Что уже в базе. Путь больше не ключ: у рипа с CUE на один файл
        //    приходится столько строк, сколько в листе дорожек.
        let knownRows: [KnownTrack] = try await db.reader.read { database in
            try KnownTrack.fetchAll(
                database,
                sql: """
                    SELECT id, relative_path, file_size, modified_at, unavailable, cue_start
                    FROM track WHERE source_id = ?
                    """,
                arguments: [source.id])
        }
        let known: [String: [KnownTrack]] = Dictionary(grouping: knownRows, by: \.relativePath)

        // 3. Инкрементальность: только новые и изменённые (mtime или size)
        var toRead: [(relative: String, url: URL, existingID: Int64?)] = []
        /// Вернувшиеся файлы — снять пометку недоступности.
        var restoredIDs: [Int64] = []
        for (relative, info) in onDisk {
            let rows = known[relative] ?? []
            if !rows.isEmpty {
                let sameSize = rows[0].fileSize == info.size
                let sameTime =
                    rows[0].modifiedAt.map {
                        abs($0.timeIntervalSince(info.mtime)) < 1.0
                    } ?? false
                // Файл не тронут, но рядом появился (или пропал) CUE-лист —
                // строк в базе столько же, сколько дорожек в листе, только
                // если разбор уже случился. Иначе перечитываем.
                let expected = cues[relative]?.tracks.count ?? 1
                if sameSize && sameTime && rows.count == expected {
                    summary.unchanged += rows.count
                    restoredIDs.append(contentsOf: rows.filter(\.unavailable).map(\.id))
                    continue
                }
                // Единственная строка — обычный трек, её id сохраняем вместе
                // с плейлистами и историей. Сегменты CUE сопоставляются по
                // началу дорожки уже при записи.
                toRead.append((relative, info.url, rows.count == 1 ? rows[0].id : nil))
            } else {
                toRead.append((relative, info.url, nil))
            }
        }

        // 4. Пропавшие пути: сначала ищем перенос — тот же size+mtime под новым
        //    именем. Узнали → трек сохраняет id (а с ним плейлисты и историю),
        //    просто меняет путь. Не узнали → помечаем недоступным, не удаляем:
        //    том мог быть отключён (D-002), файл может вернуться.
        var missing = known.filter { onDisk[$0.key] == nil }.flatMap(\.value)
        if !missing.isEmpty {
            var newIndexBySignature: [String: Int] = [:]
            for (index, item) in toRead.enumerated() where item.existingID == nil {
                if let info = onDisk[item.relative], cues[item.relative] == nil {
                    newIndexBySignature[Self.signature(size: info.size, mtime: info.mtime)] = index
                }
            }
            var stillMissing: [KnownTrack] = []
            for candidate in missing {
                // Сегменты одного файла делят подпись на всех: узнать по ней
                // переезд нельзя. Переехавший рип с CUE войдёт заново, а
                // прежние строки погасит уборка двойников ниже.
                guard candidate.cueStart == nil,
                    let size = candidate.fileSize, let mtime = candidate.modifiedAt,
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
                        try await commit(
                            batch: batch, cues: cues, source: source, summary: &summary)
                        batch.removeAll(keepingCapacity: true)
                    }
                case .failure(let error):
                    summary.failed.append(relative)
                    log("problem file: \(relative) — \(error)")
                }
            }
        }
        if !batch.isEmpty {
            try await commit(batch: batch, cues: cues, source: source, summary: &summary)
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
        cues: [String: CueContext],
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
                    // Лист главнее тегов файла: у рипа одним куском теги
                    // описывают весь диск, а названия дорожек есть только в CUE.
                    let cue = cues[relative]
                    let meta = item.meta
                    let albumTitleTag = cue?.sheet.title ?? meta.albumTitle
                    let artistTag = cue?.sheet.performer ?? meta.artist
                    let yearTag = cue?.sheet.date ?? meta.year
                    // Тег важнее файла в папке (SPEC §5.4).
                    let cover = meta.embeddedCover ?? folderCover

                    // Артист трека
                    let trackArtistID = try Self.resolveArtist(
                        name: artistTag, sortTag: meta.artistSortTag,
                        cache: &artists, database: database)

                    // Album artist по правилам §5.3
                    let albumArtistName =
                        cue?.sheet.performer ?? meta.albumArtistTag
                        ?? (meta.isCompilationTagged ? "Various Artists" : artistTag)
                    let albumArtistID = try Self.resolveArtist(
                        name: albumArtistName, sortTag: meta.albumSortTag == nil ? nil : nil,
                        cache: &artists, database: database)

                    // Альбом
                    var albumID: Int64?
                    if let albumTitle = albumTitleTag {
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
                                    albumArtist: albumArtistName, year: yearTag, date: meta.date,
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

                    if let cue {
                        // Рип с CUE: строк столько, сколько дорожек в листе.
                        // Прежние строки этого файла узнаются по началу
                        // сегмента — так правка листа не плодит двойников и не
                        // теряет id (а с ним плейлисты и историю).
                        var existing: [Double: Track] = [:]
                        for row
                            in try Track
                            .filter(Column("source_id") == source.id)
                            .filter(Column("relative_path") == item.relative)
                            .fetchAll(database)
                        {
                            if let start = row.cueStart { existing[start] = row }
                        }
                        var written: Set<Double> = []
                        for entry in cue.tracks {
                            let end = entry.end
                            let performer = entry.performer ?? artistTag
                            let artistID = try Self.resolveArtist(
                                name: performer, sortTag: nil, cache: &artists,
                                database: database)
                            var segment = Track(
                                id: existing[entry.start]?.id,
                                sourceId: source.id,
                                relativePath: item.relative,
                                fileSize: values.size,
                                modifiedAt: values.mtime,
                                title: entry.title ?? "\(meta.title) (\(entry.number))",
                                artistId: artistID,
                                albumId: albumID,
                                trackNo: entry.number,
                                discNo: meta.discNo,
                                duration: (end ?? meta.duration) - entry.start,
                                codec: meta.codec,
                                sampleRate: meta.sampleRate,
                                bitDepth: meta.bitDepth,
                                channels: meta.channels,
                                bitrate: meta.bitrate,
                                replaygainTrack: meta.replaygainTrack,
                                replaygainAlbum: meta.replaygainAlbum,
                                cueStart: entry.start,
                                cueEnd: end)
                            if segment.id != nil {
                                try segment.update(database)
                                updated += 1
                            } else {
                                try segment.insert(database)
                                added += 1
                            }
                            written.insert(entry.start)
                        }
                        // Дорожки, исчезнувшие из листа, вместе со строкой
                        // «весь файл», если он раньше играл целиком.
                        let stale =
                            try Track
                            .filter(Column("source_id") == source.id)
                            .filter(Column("relative_path") == item.relative)
                            .fetchAll(database)
                            .filter { row in
                                guard let start = row.cueStart else { return true }
                                return !written.contains(start)
                            }
                        for row in stale {
                            guard let id = row.id else { continue }
                            try Track.deleteOne(database, key: id)
                        }
                        continue
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
