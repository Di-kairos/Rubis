import AVFAudio
import EscapementCore
import Foundation
import SFBAudioEngine
import Testing

@testable import PlaybackEngine

/// R04, остаток приёмки: границы блоков, конец региона и EOF.
///
/// Регион 2–3 с того же фикстурного FLAC. Сравнение идёт с полным
/// последовательным декодом файла — как в переданных диагностиках.
struct CueSeekBoundaryTests {
    private func fixture() throws -> URL {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try #require(
            try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "flac" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }.first)
    }

    private func samples(_ decoder: any PCMDecoding, frames: Int) throws -> [Int32] {
        let format = decoder.processingFormat
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192))
        var result: [Int32] = []
        var left = frames
        while left > 0 {
            try decoder.decode(into: buffer, length: AVAudioFrameCount(min(left, 8192)))
            if buffer.frameLength == 0 { break }
            let data = try #require(buffer.int32ChannelData)
            for frame in 0..<Int(buffer.frameLength) {
                for channel in 0..<Int(format.channelCount) { result.append(data[channel][frame]) }
            }
            left -= Int(buffer.frameLength)
        }
        return result
    }

    private func region(url: URL, rate: Double) throws -> CueRegion {
        try #require(
            CueRegion(
                track: Track(
                    sourceId: "s", relativePath: url.lastPathComponent, title: "T", duration: 5,
                    codec: "flac", sampleRate: Int(rate), cueStart: 2, cueEnd: 3)))
    }

    private func opened(_ region: CueRegion, url: URL) throws -> any PCMDecoding {
        let decoder = try region.decoder(url: url)
        if !decoder.isOpen { try decoder.open() }
        return decoder
    }

    /// Границы блоков FLAC: попадание ровно на границу и соседние кадры.
    @Test(arguments: [0, 1, 4095, 4096, 4097, 8192, 44100] as [AVAudioFramePosition])
    func seekLandsOnTheRequestedFrame(offset: AVAudioFramePosition) throws {
        let url = try fixture()
        let whole = try AudioDecoder(url: url)
        try whole.open()
        defer { try? whole.close() }
        let rate = whole.processingFormat.sampleRate
        let channels = Int(whole.processingFormat.channelCount)
        let region = try region(url: url, rate: rate)
        let full = try samples(whole, frames: Int(3 * rate))

        let segment = try opened(region, url: url)
        defer { try? segment.close() }
        _ = try samples(segment, frames: 256)
        try segment.seek(to: offset)
        #expect(segment.position == offset)
        let actual = try samples(segment, frames: 256)
        let start = (Int(region.startFrame) + Int(offset)) * channels
        let expected = Array(full[start..<(start + 256 * channels)])
        #expect(actual == expected, "смещение \(offset)")
    }

    /// Конец региона и дальше: кадров нет, в соседнюю дорожку не заезжаем.
    @Test func seekToTheEndOfTheRegionYieldsNothing() throws {
        let url = try fixture()
        let probe = try AudioDecoder(url: url)
        try probe.open()
        let rate = probe.processingFormat.sampleRate
        try probe.close()
        let region = try region(url: url, rate: rate)

        let segment = try opened(region, url: url)
        defer { try? segment.close() }
        try segment.seek(to: region.frameLength)
        #expect(try samples(segment, frames: 512).isEmpty)
        // Запрос за концом дорожки прижимается к её концу, а не открывает соседнюю.
        try segment.seek(to: region.frameLength + 10 * AVAudioFramePosition(rate))
        #expect(segment.position == region.frameLength)
        #expect(try samples(segment, frames: 512).isEmpty)
    }

    /// После перемотки у дорожки остаётся ровно её хвост, и длина не «тает».
    @Test func tailAfterSeekStopsAtTheRegionEnd() throws {
        let url = try fixture()
        let probe = try AudioDecoder(url: url)
        try probe.open()
        let rate = probe.processingFormat.sampleRate
        let channels = Int(probe.processingFormat.channelCount)
        try probe.close()
        let region = try region(url: url, rate: rate)

        let segment = try opened(region, url: url)
        defer { try? segment.close() }
        let offset = region.frameLength - 5000
        try segment.seek(to: offset)
        let tail = try samples(segment, frames: Int(region.frameLength))
        #expect(tail.count == 5000 * channels)
        #expect(segment.length == region.frameLength)
        #expect(segment.position == region.frameLength)
    }
}
