import EscapementCore
import Foundation
import Testing

@testable import PlaybackEngine

/// Проба скачанного файла (аудит 2026-09-12, #18/#14): звук проходит с
/// настоящим форматом, ответ сервера с кодом 200 — нет.
struct AudioProbeTests {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

    private func scratch(_ name: String, _ bytes: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "probe-\(UUID())-\(name)")
        try bytes.write(to: url)
        return url
    }

    @Test func realAudioPassesWithItsOwnFormat() throws {
        let flac = Self.fixtures.appendingPathComponent("sine-96000-24.flac")
        guard FileManager.default.fileExists(atPath: flac.path) else { return }
        // Расширение — от сервера, ему не верим: копия без расширения.
        let bare = try scratch("bare", try Data(contentsOf: flac))
        defer { try? FileManager.default.removeItem(at: bare) }
        let format = try AudioProbe.validate(bare)
        #expect(format.sampleRate == 96000)
        #expect(format.bitDepth == 24)
        #expect(format.channels == 2)
        #expect(!format.isDSD)
    }

    @Test func serverErrorBodiesAreRejected() throws {
        let bodies: [(String, String)] = [
            (
                "xml",
                "<subsonic-response status=\"failed\"><error code=\"40\"/></subsonic-response>"
            ),
            ("json", "{\"subsonic-response\":{\"status\":\"failed\"}}"),
            ("html", "<!doctype html><html><body>Sign in</body></html>"),
            ("empty", ""),
        ]
        for (name, body) in bodies {
            let url = try scratch(name, Data(body.utf8))
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(throws: PlaybackError.self, "\(name) must not pass") {
                try AudioProbe.validate(url)
            }
        }
    }
}
