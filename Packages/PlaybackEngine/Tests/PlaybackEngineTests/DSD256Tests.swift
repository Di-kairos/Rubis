import AVFoundation
import Foundation
import SFBAudioEngine
import Testing

/// Живой баг S23: DSD256 DSF не открывался вовсе — апстримный SFBDSFDecoder
/// принимает только DSD64/128. Тест держит пин на форк `0.13.0-rubis.1`:
/// вернись зависимость на апстрим — он упадёт.
struct DSD256Tests {
    /// Минимальный стерео DSF: заголовок, `fmt `, один блок 4096 байт на канал.
    /// ffmpeg DSF не пишет, поэтому файл собирается здесь (спецификация DSF 1.01).
    private func makeDSF(rate: UInt32) throws -> URL {
        let block = 4096
        let channels = 2
        var data = Data()
        func u32(_ v: UInt32) {
            withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
        }
        func u64(_ v: UInt64) {
            withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
        }
        let payload = block * channels
        data.append(contentsOf: Array("DSD ".utf8))
        u64(28)
        u64(UInt64(28 + 52 + 12 + payload))
        u64(0)
        data.append(contentsOf: Array("fmt ".utf8))
        u64(52)
        u32(1)  // format version
        u32(0)  // DSD raw
        u32(2)  // channel type: stereo
        u32(UInt32(channels))
        u32(rate)
        u32(1)  // bits per sample, LSB first
        u64(UInt64(block * 8))  // samples per channel
        u32(UInt32(block))
        u32(0)
        data.append(contentsOf: Array("data".utf8))
        u64(UInt64(12 + payload))
        data.append(Data(repeating: 0x69, count: payload))  // DSD silence pattern
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsd\(rate)-\(UUID().uuidString).dsf")
        try data.write(to: url)
        return url
    }

    @Test func dsd256DsfGoesOutAsDoPAt705k() throws {
        let url = try makeDSF(rate: 11_289_600)
        defer { try? FileManager.default.removeItem(at: url) }

        let dop = try DoPDecoder(decoder: try DSDDecoder(url: url))
        try dop.open()
        #expect(dop.processingFormat.sampleRate == 705_600)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: dop.processingFormat, frameCapacity: 512))
        try dop.decode(into: buffer, length: 512)
        #expect(buffer.frameLength == 512)
    }
}
