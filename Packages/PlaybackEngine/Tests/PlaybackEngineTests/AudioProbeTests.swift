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

    /// DSF собирается руками: заголовок DSD/fmt/data по спецификации Sony.
    /// `dataBytes` — тело data-чанка; ноль байт — «заголовок без звука».
    private func dsf(dataBytes: Int) -> Data {
        var bytes = Data()
        func u32(_ v: UInt32) {
            withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) }
        }
        func u64(_ v: UInt64) {
            withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) }
        }
        let total = UInt64(28 + 52 + 12 + dataBytes)
        bytes.append(contentsOf: Array("DSD ".utf8)); u64(28); u64(total); u64(0)
        bytes.append(contentsOf: Array("fmt ".utf8)); u64(52)
        u32(1); u32(0); u32(2); u32(2); u32(2_822_400); u32(1)
        u64(UInt64(dataBytes / 2 * 8)); u32(4096); u32(0)
        bytes.append(contentsOf: Array("data".utf8)); u64(UInt64(12 + dataBytes))
        bytes.append(Data(count: dataBytes))
        return bytes
    }

    @Test func dsdWithAudioPassesAsDSD() throws {
        let url = try scratch("silence.dsf", dsf(dataBytes: 8192))
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try AudioProbe.validate(url)
        #expect(format.isDSD)
        #expect(format.sampleRate == 2_822_400)
        #expect(format.channels == 2)
    }

    @Test func truncatedDSDWithoutDataIsRejected() throws {
        let url = try scratch("empty.dsf", dsf(dataBytes: 0))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PlaybackError.self) { try AudioProbe.validate(url) }
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
