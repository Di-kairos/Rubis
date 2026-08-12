import AVFAudio
import EscapementCore
import SFBAudioEngine
import Testing

import class Foundation.FileManager
import struct Foundation.URL

@testable import PlaybackEngine

/// Живой декод сегмента CUE (D-013): арифметика `CueRegion` ничего не стоит,
/// если декодер отдаёт не те кадры. Берём фикстуру из Fixtures/ (нет — скип),
/// декодируем регион и сверяем с тем же куском полного декода.
struct CueDecodeTests {

    private static let fixture: URL? = {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // PlaybackEngineTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // PlaybackEngine
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Fixtures")
        return
            (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "flac" }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .first
    }()

    static var fixturesAvailable: Bool { fixture != nil }

    /// Декодирует файл целиком в интерливленный Int32 — точное представление
    /// для FLAC ≤ 24 бит, значит сравнение идёт по битам, а не «на слух».
    private func samples(
        from decoder: any PCMDecoding, format: AVAudioFormat, limit: AVAudioFrameCount
    ) throws -> [Int32] {
        var all: [Int32] = []
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192))
        while all.count < Int(limit) * Int(format.channelCount) {
            try decoder.decode(into: buffer, length: 8192)
            if buffer.frameLength == 0 { break }
            let data = try #require(buffer.int32ChannelData)
            for frame in 0..<Int(buffer.frameLength) {
                for channel in 0..<Int(format.channelCount) {
                    all.append(data[channel][frame])
                }
            }
        }
        return all
    }

    @Test(.enabled(if: fixturesAvailable)) func regionDecodesExactlyItsFrames() throws {
        let url = try #require(Self.fixture)

        let whole = try AudioDecoder(url: url)
        try whole.open()  // до open() формат пустой, частота нулевая
        let format = whole.processingFormat
        let channels = Int(format.channelCount)

        // Регион: со второй секунды на одну секунду. Фикстуры пятисекундные,
        // так что обе границы лежат внутри файла.
        let region = try #require(
            CueRegion(
                track: Track(
                    sourceId: "s", relativePath: url.lastPathComponent, title: "T", duration: 5,
                    codec: "flac", sampleRate: Int(format.sampleRate), cueStart: 2, cueEnd: 3)))

        let expectedFrames = AVAudioFrameCount(region.frameLength)
        let full = try samples(
            from: whole, format: format,
            limit: AVAudioFrameCount(region.startFrame) + expectedFrames)

        // Фабрика открывает декодер сама, когда доедает лишние кадры; повторный
        // open вернул бы его на старт — так же, как это делает AudioPlayer.
        let segment = try region.decoder(url: url)
        if !segment.isOpen { try segment.open() }
        // Читаем кусками по 8192 кадра, поэтому берём с запасом и режем ровно
        // по длине сегмента.
        let wanted = Int(expectedFrames) * channels
        let part = Array(
            try samples(from: segment, format: format, limit: expectedFrames).prefix(wanted))

        #expect(part.count == wanted)
        let offset = Int(region.startFrame) * channels
        #expect(part == Array(full[offset..<(offset + wanted)]))
    }
}
