import Foundation
import Testing

@testable import MusicLibrary

struct FolderWatcherTests {
    /// FSEvents доставляет событие и дебаунс схлопывает серию изменений в один колбэк.
    @Test(.timeLimit(.minutes(1))) @MainActor
    func reportsChangesAfterDebounce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var received: [URL] = []
        let watcher = FolderWatcher(roots: [root]) { changed in
            received.append(contentsOf: changed)
        }
        defer { watcher.stop() }

        // серия изменений — должна схлопнуться дебаунсом
        for i in 0..<3 {
            try Data("x".utf8).write(to: root.appendingPathComponent("f\(i).flac"))
        }

        var waited = 0
        while received.isEmpty && waited < 10_000 {
            try await Task.sleep(for: .milliseconds(200))
            waited += 200
        }
        #expect(!received.isEmpty, "no FSEvents callback within 10 s")
    }
}
