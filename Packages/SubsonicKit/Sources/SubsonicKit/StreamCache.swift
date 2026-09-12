import CryptoKit
import Foundation

/// Кэш скачанных с сервера файлов (SPEC §6.2, фаза 6 pack 5).
///
/// Bit-perfect и поток по сети не дружат: движку нужна точная частота ДО старта,
/// а сеть проваливается на середине. Поэтому трек сначала скачивается целиком,
/// а играет уже файл — тем же путём, что и локальный, без отдельной ветки в
/// аудио-движке.
///
/// Имя файла детерминировано: один и тот же трек всегда лежит по одному адресу,
/// поэтому очередь можно собрать заранее, а докачать — к моменту, когда движок
/// до неё дойдёт.
public actor StreamCache {
    /// Загрузка одного адреса во временный файл. Подменяется в тестах.
    public typealias Download = @Sendable (URL) async throws -> URL
    /// Проверка скачанного файла до того, как он станет записью кэша. Бросает
    /// — файл выбрасывается, ошибка уходит вызывающему. Сервер отвечает
    /// HTTP 200 и на ошибку API, и страницей входа; без проверки такой ответ
    /// лёг бы в кэш навсегда. Сам кэш про звук не знает — проверку даёт
    /// слой воспроизведения.
    public typealias Validate = @Sendable (URL) throws -> Void

    /// Сколько файлов кэш держит при любом лимите. Играющий трек и
    /// префетченный следующий вытеснять нельзя — иначе кэш убивает то самое
    /// воспроизведение, ради которого он существует.
    static let protectedCount = 2

    private let root: URL
    private let download: Download
    private let validate: Validate
    /// Потолок кэша в байтах (SPEC §6.2, по умолчанию 8 ГБ).
    private var limit: Int64
    /// Идущие загрузки: второй запрос того же трека ждёт первую, а не качает
    /// файл дважды (Play и префетч легко сходятся на одном треке).
    private var inFlight: [String: Task<URL, Error>] = [:]

    /// Корень по умолчанию — `~/Library/Caches/Escapement/stream`.
    public init(
        root: URL? = nil,
        limitBytes: Int64 = 8 * 1024 * 1024 * 1024,
        download: @escaping Download = StreamCache.urlSessionDownload,
        validate: @escaping Validate = { _ in }
    )
        throws
    {
        self.limit = limitBytes
        self.validate = validate
        self.root =
            root
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Escapement/stream", isDirectory: true)
        self.download = download
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    /// Адрес, по которому трек лежит или будет лежать. Идентификатор сервера
    /// в имя файла не попадает как есть — он приходит снаружи и может
    /// содержать что угодно; берём его отпечаток.
    public nonisolated func location(remoteId: String, codec: String) -> URL {
        let digest = SHA256.hash(data: Data(remoteId.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(digest).\(Self.suffix(for: codec))")
    }

    /// Расширение файла в кэше. `codec` приходит с сервера как есть — строка
    /// с `/` или `..` вышла бы за пределы каталога кэша. Только короткие
    /// ASCII-буквы и цифры, всё остальное — `audio`.
    static func suffix(for codec: String) -> String {
        let clean =
            !codec.isEmpty && codec.count <= 8 && codec != "unknown"
            && codec.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return clean ? codec.lowercased() : "audio"
    }

    /// Файл уже на диске?
    public nonisolated func isCached(remoteId: String, codec: String) -> Bool {
        FileManager.default.fileExists(atPath: location(remoteId: remoteId, codec: codec).path)
    }

    /// Файл трека: с диска, если он там есть, иначе качает целиком.
    ///
    /// Скачанное кладётся на место одним движением — оборванная загрузка не
    /// оставляет обрубок, который потом сыграет как испорченный трек.
    ///
    /// ponytail: кэш растёт без предела — лимит и вытеснение идут pack'ом 6.
    public func file(remoteId: String, codec: String, from url: URL) async throws -> URL {
        let destination = location(remoteId: remoteId, codec: codec)
        if FileManager.default.fileExists(atPath: destination.path) {
            touch(destination)
            return destination
        }
        if let running = inFlight[destination.path] { return try await running.value }

        let task = Task<URL, Error> { [download, validate] in
            let temporary = try await download(url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try validate(temporary)
            // Второй запрос мог успеть первым — победитель уже на месте.
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            return destination
        }
        inFlight[destination.path] = task
        defer { inFlight[destination.path] = nil }
        let file = try await task.value
        evict()
        return file
    }

    // MARK: - Лимит (SPEC §6.2)

    /// Новый потолок применяется сразу: уменьшил лимит — лишнее уехало.
    public func setLimit(bytes: Int64) {
        limit = bytes
        evict()
    }

    /// Сколько кэш занимает сейчас — для строки в настройках.
    public func size() -> Int64 {
        entries().reduce(0) { $0 + $1.size }
    }

    /// Ручная очистка. Играющий трек уже открыт движком: файл исчезает из
    /// каталога, но воспроизведение доигрывает по открытому дескриптору.
    /// Идущие загрузки отменяются — иначе они донесли бы в пустой кэш то,
    /// что владелец только что выбросил.
    public func clear() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        for entry in entries() {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    /// Выбрасывает один объект: файл прошёл проверку, но декодер на нём
    /// споткнулся позже — следующая попытка качает заново.
    public func remove(remoteId: String, codec: String) {
        try? FileManager.default.removeItem(at: location(remoteId: remoteId, codec: codec))
    }

    /// Вытеснение по давности использования: свежие остаются, старые уходят,
    /// пока кэш не влезет в лимит. Два самых свежих не трогаем никогда.
    private func evict() {
        let sorted = entries().sorted { $0.used > $1.used }
        var total: Int64 = 0
        for (position, entry) in sorted.enumerated() {
            total += entry.size
            guard position >= Self.protectedCount, total > limit else { continue }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    private struct Entry {
        let url: URL
        let size: Int64
        let used: Date
    }

    private func entries() -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: keys)) ?? []
        return files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                let size = values.fileSize
            else { return nil }
            return Entry(
                url: url, size: Int64(size),
                used: values.contentModificationDate ?? .distantPast)
        }
    }

    /// Отметка «файлом только что пользовались» — по ней и считается давность.
    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: url.path)
    }

    /// Загрузка по умолчанию: временный файл системной сессии.
    public static let urlSessionDownload: Download = { url in
        let (temporary, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: temporary)
            throw SubsonicError.http(http.statusCode)
        }
        // Системный временный файл живёт до конца обработчика — переносим его
        // в свой каталог, чтобы дальше распоряжаться им спокойно.
        let staged = temporary.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: temporary, to: staged)
        return staged
    }
}
