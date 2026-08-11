import Foundation
import Testing

@testable import SubsonicKit

/// Кэш скачанных треков (pack 5). Сеть подменена: тесты пишут в свой каталог
/// и никуда не ходят.
struct StreamCacheTests {

    /// Счётчик загрузок — по нему видно, что кэш действительно кэширует.
    private final class Recorder: @unchecked Sendable {
        var calls = 0
        var bytes = Data("audio".utf8)
        var failure: Error?
    }

    private func makeCache(
        _ recorder: Recorder, root: URL, limitBytes: Int64 = 8 * 1024 * 1024 * 1024
    ) throws -> StreamCache {
        try StreamCache(root: root, limitBytes: limitBytes) { _ in
            recorder.calls += 1
            if let failure = recorder.failure { throw failure }
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try recorder.bytes.write(to: temporary)
            return temporary
        }
    }

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private let remoteURL = URL(string: "https://music.example.com/rest/download?id=tr-1")!

    @Test func trackIsDownloadedOnceAndReadAgainFromDisk() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = Recorder()
        let cache = try makeCache(recorder, root: root)

        let first = try await cache.file(remoteId: "tr-1", codec: "flac", from: remoteURL)
        let second = try await cache.file(remoteId: "tr-1", codec: "flac", from: remoteURL)

        #expect(first == second)
        #expect(recorder.calls == 1)
        #expect(try Data(contentsOf: first) == Data("audio".utf8))
        #expect(first.pathExtension == "flac")
    }

    @Test func twoRequestsForTheSameTrackShareOneDownload() async throws {
        // Play и префетч сходятся на одном треке постоянно — файл не должен
        // качаться дважды и уж точно не должен переезжать под играющим.
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = Recorder()
        let cache = try makeCache(recorder, root: root)

        async let one = cache.file(remoteId: "tr-1", codec: "flac", from: remoteURL)
        async let two = cache.file(remoteId: "tr-1", codec: "flac", from: remoteURL)
        let urls = try await [one, two]

        #expect(urls[0] == urls[1])
        #expect(recorder.calls == 1)
    }

    @Test func differentTracksLandInDifferentFiles() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try makeCache(Recorder(), root: root)

        #expect(
            cache.location(remoteId: "tr-1", codec: "flac")
                != cache.location(remoteId: "tr-2", codec: "flac"))
        // Адрес детерминирован: очередь собирается до того, как файл приехал.
        #expect(
            cache.location(remoteId: "tr-1", codec: "flac")
                == cache.location(remoteId: "tr-1", codec: "flac"))
        #expect(cache.location(remoteId: "tr-1", codec: "unknown").pathExtension == "audio")
    }

    @Test func failedDownloadLeavesNothingBehind() async throws {
        // Обрубок на диске сыграл бы как испорченный трек — хуже, чем ошибка.
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = Recorder()
        recorder.failure = SubsonicError.http(503)
        let cache = try makeCache(recorder, root: root)

        await #expect(throws: SubsonicError.http(503)) {
            _ = try await cache.file(remoteId: "tr-1", codec: "flac", from: remoteURL)
        }
        #expect(!cache.isCached(remoteId: "tr-1", codec: "flac"))

        // После провала трек качается заново, а не считается «уже пробовали».
        recorder.failure = nil
        _ = try await cache.file(remoteId: "tr-1", codec: "flac", from: remoteURL)
        #expect(cache.isCached(remoteId: "tr-1", codec: "flac"))
        #expect(recorder.calls == 2)
    }

    // MARK: - Лимит и вытеснение (pack 6)

    /// Файлы по 100 байт: лимит считается в них, а не в мегабайтах.
    private func makeCountingCache(root: URL, limitBytes: Int64) throws -> StreamCache {
        let recorder = Recorder()
        recorder.bytes = Data(repeating: 0x41, count: 100)
        return try makeCache(recorder, root: root, limitBytes: limitBytes)
    }

    @Test func oldestTracksLeaveWhenTheCacheIsFull() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try makeCountingCache(root: root, limitBytes: 250)

        for id in ["tr-1", "tr-2", "tr-3", "tr-4"] {
            _ = try await cache.file(remoteId: id, codec: "flac", from: remoteURL)
        }

        #expect(cache.isCached(remoteId: "tr-4", codec: "flac"))
        #expect(cache.isCached(remoteId: "tr-3", codec: "flac"))
        #expect(!cache.isCached(remoteId: "tr-2", codec: "flac"))
        #expect(!cache.isCached(remoteId: "tr-1", codec: "flac"))
        #expect(await cache.size() == 200)
    }

    @Test func aTrackPlayedAgainOutlivesOlderNeighbours() async throws {
        // Давность считается по последнему обращению, а не по загрузке:
        // любимый альбом не должен вымываться свежескачанным.
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try makeCountingCache(root: root, limitBytes: 250)

        _ = try await cache.file(remoteId: "old-favourite", codec: "flac", from: remoteURL)
        _ = try await cache.file(remoteId: "tr-2", codec: "flac", from: remoteURL)
        _ = try await cache.file(remoteId: "tr-3", codec: "flac", from: remoteURL)
        // Слушаем первый ещё раз — он снова самый свежий.
        _ = try await cache.file(remoteId: "old-favourite", codec: "flac", from: remoteURL)
        _ = try await cache.file(remoteId: "tr-4", codec: "flac", from: remoteURL)

        #expect(cache.isCached(remoteId: "old-favourite", codec: "flac"))
        #expect(cache.isCached(remoteId: "tr-4", codec: "flac"))
        #expect(!cache.isCached(remoteId: "tr-2", codec: "flac"))
    }

    @Test func twoNewestSurviveEvenAnAbsurdLimit() async throws {
        // Играющий трек и префетченный следующий вытеснять нельзя — иначе
        // кэш убивает то воспроизведение, ради которого он и заведён.
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try makeCountingCache(root: root, limitBytes: 1)

        for id in ["tr-1", "tr-2", "tr-3"] {
            _ = try await cache.file(remoteId: id, codec: "flac", from: remoteURL)
        }

        #expect(cache.isCached(remoteId: "tr-3", codec: "flac"))
        #expect(cache.isCached(remoteId: "tr-2", codec: "flac"))
        #expect(!cache.isCached(remoteId: "tr-1", codec: "flac"))
    }

    @Test func loweredLimitTakesEffectAtOnce() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try makeCountingCache(root: root, limitBytes: 10_000)

        for id in ["tr-1", "tr-2", "tr-3", "tr-4"] {
            _ = try await cache.file(remoteId: id, codec: "flac", from: remoteURL)
        }
        #expect(await cache.size() == 400)

        await cache.setLimit(bytes: 250)
        #expect(await cache.size() == 200)
    }

    @Test func clearEmptiesTheWholeCache() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try makeCountingCache(root: root, limitBytes: 10_000)

        _ = try await cache.file(remoteId: "tr-1", codec: "flac", from: remoteURL)
        _ = try await cache.file(remoteId: "tr-2", codec: "flac", from: remoteURL)

        await cache.clear()
        #expect(await cache.size() == 0)
        #expect(!cache.isCached(remoteId: "tr-1", codec: "flac"))
    }
}
