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

    private let root: URL
    private let download: Download
    /// Идущие загрузки: второй запрос того же трека ждёт первую, а не качает
    /// файл дважды (Play и префетч легко сходятся на одном треке).
    private var inFlight: [String: Task<URL, Error>] = [:]

    /// Корень по умолчанию — `~/Library/Caches/Escapement/stream`.
    public init(root: URL? = nil, download: @escaping Download = StreamCache.urlSessionDownload)
        throws
    {
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
        let suffix = codec.isEmpty || codec == "unknown" ? "audio" : codec
        return root.appendingPathComponent("\(digest).\(suffix)")
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
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        if let running = inFlight[destination.path] { return try await running.value }

        let task = Task<URL, Error> { [download] in
            let temporary = try await download(url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            // Второй запрос мог успеть первым — победитель уже на месте.
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            return destination
        }
        inFlight[destination.path] = task
        defer { inFlight[destination.path] = nil }
        return try await task.value
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
