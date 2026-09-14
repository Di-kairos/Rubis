import Foundation
import Testing

@testable import SubsonicKit

private actor ReauditDownloadGate {
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

/// Загрузка уже завершилась снаружи, но её continuation приходит после Clear.
struct ReauditRegressionTests {
    @Test func clearMustRejectLateDownloadCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reaudit-cache-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let download = root.appendingPathComponent("download.bin")
        try Data([1, 2, 3]).write(to: download)
        let gate = ReauditDownloadGate()
        let cache = try StreamCache(
            root: root.appendingPathComponent("cache"),
            download: { _ in
                // Cancellation кооперативна: моделируем уже готовый результат.
                await gate.hold()
            })
        let url = try #require(URL(string: "https://example.test/rest/stream.view?u=auditor&id=1"))
        let fetch = Task { try await cache.file(remoteId: "1", codec: "flac", from: url) }
        await gate.waitUntilStarted()
        await cache.clear()
        await gate.finish(download)
        _ = await fetch.result
        let cached = cache.isCached(
            remoteId: "1", codec: "flac", scope: StreamCache.scope(for: url))
        print("REAUDIT cache exists after Clear and late completion: \(cached)")
        #expect(!cached)
    }
}
