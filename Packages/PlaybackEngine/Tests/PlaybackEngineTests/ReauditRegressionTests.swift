import AVFAudio
import EscapementCore
import Foundation
import SFBAudioEngine
import Testing

@testable import PlaybackEngine

/// Повторный аудит: после перемотки проверяем PCM, а не только часы.
struct ReauditRegressionTests {
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

    private func checkSeek(seconds: Double) throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        let url = try #require(
            try FileManager.default.contentsOfDirectory(
                at: fixtures, includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "flac" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.first)
        let whole = try AudioDecoder(url: url)
        try whole.open()
        defer { try? whole.close() }
        let rate = whole.processingFormat.sampleRate
        let channels = Int(whole.processingFormat.channelCount)
        let region = try #require(
            CueRegion(
                track: Track(
                    sourceId: "s", relativePath: url.lastPathComponent, title: "T", duration: 5,
                    codec: "flac", sampleRate: Int(rate), cueStart: 2, cueEnd: 3)))
        let full = try samples(whole, frames: Int(3 * rate))
        let segment = try region.decoder(url: url)
        if !segment.isOpen { try segment.open() }
        defer { try? segment.close() }
        // Отходим от начала: seek(0) должен реально переустановить декодер.
        _ = try samples(segment, frames: 256)
        let target = AVAudioFramePosition(seconds * rate)
        try segment.seek(to: target)
        let reported = segment.position
        let actual = try samples(segment, frames: 512)
        let offset = (Int(region.startFrame) + Int(target)) * channels
        let expected = Array(full[offset..<(offset + 512 * channels)])
        let mismatch = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?
            .offset
        print(
            "REAUDIT CUE seek=\(target) position=\(reported) rate=\(rate) samples=\(actual.count) firstMismatch=\(String(describing: mismatch))"
        )
        #expect(reported == target)
        #expect(actual.count == expected.count)
        #expect(mismatch == nil)
    }

    @Test func cueSeekToZeroMustReturnOriginalPCM() throws { try checkSeek(seconds: 0) }
    @Test func cueSeekToMiddleMustReturnOriginalPCM() throws { try checkSeek(seconds: 0.5) }
}
