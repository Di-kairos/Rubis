import AVFAudio
import EscapementCore
import Foundation
import SFBAudioEngine

/// Проверка файла перед тем, как он станет записью кэша серверных треков.
///
/// Сервер отвечает HTTP 200 и на ошибку API (XML/JSON), и страницей входа
/// (HTML); загрузчик смотрит только на статус. Такой файл лёг бы в кэш
/// навсегда и «играл» бы ошибкой при каждом запуске. Открываем тем же
/// декодером, что и при воспроизведении, по содержимому, а не по расширению
/// (расширение — от сервера), требуем конечную частоту, разумное число
/// каналов и хотя бы один прочитанный блок. Целостность всего файла это не
/// доказывает — поздний сбой декодера кэш всё равно инвалидирует.
public enum AudioProbe {
    /// Формат, который декодер увидел на самом деле.
    public struct Format: Sendable, Equatable {
        public let sampleRate: Double
        public let bitDepth: Int?
        public let channels: Int
        public let isDSD: Bool
    }

    /// Бросает `PlaybackError.decodingFailed`, если файл не открывается как
    /// звук или не отдаёт ни кадра.
    @discardableResult
    public static func validate(_ url: URL) throws -> Format {
        if let dsd = try? DSDDecoder(url: url, detectContentType: true) {
            try dsd.open()
            let format = dsd.processingFormat
            guard format.sampleRate.isFinite, format.sampleRate > 0,
                (1...8).contains(format.channelCount)
            else { throw PlaybackError.decodingFailed("DSD stream reports no usable format") }
            // Как и у PCM: заголовок без данных — не запись кэша (§13.3, #18).
            let bytesPerPacket = Int(format.streamDescription.pointee.mBytesPerPacket)
            guard bytesPerPacket > 0 else {
                throw PlaybackError.decodingFailed("DSD stream reports no packet size")
            }
            let buffer = AVAudioCompressedBuffer(
                format: format, packetCapacity: 64, maximumPacketSize: bytesPerPacket)
            try dsd.decode(into: buffer, count: 64)
            guard buffer.packetCount > 0 else {
                throw PlaybackError.decodingFailed("valid DSD header but no audio data")
            }
            return Format(
                sampleRate: format.sampleRate, bitDepth: 1, channels: Int(format.channelCount),
                isDSD: true)
        }
        let decoder: AudioDecoder
        do {
            decoder = try AudioDecoder(url: url, detectContentType: true)
            try decoder.open()
        } catch {
            throw PlaybackError.decodingFailed("not an audio file: \(error.localizedDescription)")
        }
        let format = decoder.processingFormat
        guard format.sampleRate.isFinite, format.sampleRate > 0,
            (1...8).contains(format.channelCount)
        else { throw PlaybackError.decodingFailed("stream reports no usable format") }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
            throw PlaybackError.decodingFailed("cannot allocate a probe buffer")
        }
        try decoder.decode(into: buffer, length: 4096)
        guard buffer.frameLength > 0 else {
            throw PlaybackError.decodingFailed("valid header but no audio data")
        }
        return Format(
            sampleRate: format.sampleRate, bitDepth: bitDepth(of: decoder),
            channels: Int(format.channelCount), isDSD: false)
    }

    /// Разрядность источника из формата контейнера; 0 — неизвестна (сжатые
    /// кодеки её не объявляют), и тогда это `nil`, а не подставленные 16.
    public static func bitDepth(of decoder: any PCMDecoding) -> Int? {
        let bits = Int(decoder.sourceFormat.streamDescription.pointee.mBitsPerChannel)
        return bits > 0 ? bits : nil
    }
}
