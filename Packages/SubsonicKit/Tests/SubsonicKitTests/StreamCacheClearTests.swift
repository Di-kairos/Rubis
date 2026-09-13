import Foundation
import Testing

@testable import SubsonicKit

/// Ворота одной загрузки: тест сам решает, когда она «доедет».
private actor Gate {
    private var response: CheckedContinuation<URL, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func hold() async -> URL {
        await withCheckedContinuation { continuation in
            response = continuation
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        if response != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish(_ url: URL) { response?.resume(returning: url); response = nil }
}

/// Раздаёт загрузкам разные ворота по порядку вызова.
private actor GateQueue {
    private var gates: [Gate]
    private var next = 0
    init(_ gates: [Gate]) { self.gates = gates }
    func take() -> Gate {
        let gate = gates[min(next, gates.count - 1)]
        next += 1
        return gate
    }
}

/// R05, вторая половина приёмки: Clear → новая загрузка того же ключа →
/// позднее завершение старой. Старые байты не возвращаются, новая задача
/// остаётся на учёте и доносит свои.
struct StreamCacheClearTests {
    @Test func lateOldDownloadDoesNotEvictOrOverwriteTheNewOne() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cache-clear-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let oldBytes = root.appendingPathComponent("old.bin")
        let newBytes = root.appendingPathComponent("new.bin")
        try Data([1, 1, 1]).write(to: oldBytes)
        try Data([2, 2, 2, 2]).write(to: newBytes)

        let first = Gate()
        let second = Gate()
        let queue = GateQueue([first, second])
        let cache = try StreamCache(
            root: root.appendingPathComponent("cache"),
            download: { _ in await queue.take().hold() })

        let url = try #require(URL(string: "https://example.test/rest/stream.view?u=dan&id=7"))
        let scope = StreamCache.scope(for: url)
        let stale = Task { try await cache.file(remoteId: "7", codec: "flac", from: url) }
        await first.waitUntilStarted()
        await cache.clear()

        // Тот же трек качается заново уже после очистки.
        let fresh = Task { try await cache.file(remoteId: "7", codec: "flac", from: url) }
        await second.waitUntilStarted()
        // Старая загрузка доезжает последней — учёт новой она трогать не должна.
        await first.finish(oldBytes)
        _ = await stale.result
        await second.finish(newBytes)

        let file = try await fresh.value
        #expect(cache.isCached(remoteId: "7", codec: "flac", scope: scope))
        #expect(try Data(contentsOf: file) == Data([2, 2, 2, 2]))
    }
}
