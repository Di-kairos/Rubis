import EscapementCore
import Foundation
import MusicLibrary
import SubsonicKit

/// Треки с сервера как обычные файлы (SPEC §6.2, фаза 6 pack 5).
///
/// Download-then-play: трек скачивается целиком, а играет уже файл — движок
/// про сервер не знает вовсе. Здесь живёт всё, что нужно, чтобы это выглядело
/// как локальная музыка: адрес в кэше, докачка перед стартом и префетч
/// следующего трека во время текущего.
actor RemotePlayback {
    private let cache: StreamCache
    private let ledger: NetworkLedger
    /// Клиенты по источникам: сборка лезет в связку ключей, а дёргать её на
    /// каждый трек — и медленно, и лишний повод для диалога macOS.
    private var clients: [String: SubsonicClient] = [:]

    init(cache: StreamCache, ledger: NetworkLedger) {
        self.cache = cache
        self.ledger = ledger
    }

    /// Трек живёт на сервере, а не в папке.
    nonisolated static func isRemote(_ track: Track) -> Bool {
        track.remoteId != nil && track.relativePath == nil
    }

    /// Адрес, по которому трек лежит или будет лежать. Очередь собирается
    /// заранее — файл к этому моменту может ещё качаться.
    nonisolated func location(for track: Track) -> URL? {
        guard let remoteId = track.remoteId else { return nil }
        return cache.location(remoteId: remoteId, codec: track.codec)
    }

    /// Потолок кэша из настроек (SPEC §6.2). Уменьшил — лишнее уезжает сразу.
    func setCacheLimit(gigabytes: Int) async {
        await cache.setLimit(bytes: Int64(max(1, gigabytes)) * 1024 * 1024 * 1024)
    }

    /// Сколько скачанного лежит на диске — строка в настройках.
    func cacheSize() async -> Int64 {
        await cache.size()
    }

    /// Ручная очистка кэша.
    func clearCache() async {
        await cache.clear()
    }

    func register(source: Source) {
        guard source.kind == .subsonic, let client = SubsonicAccount.client(for: source) else {
            return
        }
        clients[source.id] = client
    }

    /// Сервер отвечает? Один `ping` (SPEC §6.3). Источник без пароля в связке
    /// считается недоступным: играть с него всё равно нечем.
    func isReachable(sourceId: String) async -> Bool {
        guard let client = clients[sourceId] else { return false }
        do {
            try await client.ping()
            await ledger.record(
                host: client.host, purpose: "Server check", succeeded: true, bytes: 0)
            return true
        } catch {
            await ledger.record(
                host: client.host, purpose: "Server check", succeeded: false, bytes: 0)
            return false
        }
    }

    /// Файл трека на диске: уже скачанный или скачанный сейчас.
    /// Локальные треки и треки без клиента возвращают `nil` — вызывающая
    /// сторона играет их как обычно или пропускает.
    @discardableResult
    func fetch(_ track: Track) async -> URL? {
        guard Self.isRemote(track), let remoteId = track.remoteId,
            let client = clients[track.sourceId],
            let url = client.downloadURL(id: remoteId)
        else { return nil }
        if cache.isCached(remoteId: remoteId, codec: track.codec) {
            return cache.location(remoteId: remoteId, codec: track.codec)
        }
        do {
            let file = try await cache.file(remoteId: remoteId, codec: track.codec, from: url)
            await record(url: url, succeeded: true, file: file)
            return file
        } catch {
            Log.library.error("stream download failed: \(error, privacy: .public)")
            await record(url: url, succeeded: false, file: nil)
            return nil
        }
    }

    /// Скачанное считается по факту: панель Settings → Network обещает
    /// показывать каждый исходящий запрос (фишка D).
    private func record(url: URL, succeeded: Bool, file: URL?) async {
        let bytes =
            file.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] }
            as? Int ?? 0
        await ledger.record(
            host: url.host ?? "", purpose: "Track download", succeeded: succeeded, bytes: bytes)
    }
}
