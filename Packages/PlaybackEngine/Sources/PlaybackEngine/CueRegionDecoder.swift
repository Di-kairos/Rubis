import AVFAudio
import EscapementCore
import Foundation
import SFBAudioEngine

extension CueRegion {

    /// Декодер сегмента, отдающий кадры ровно с `startFrame`.
    ///
    /// Просто `AudioRegionDecoder` этого не делает: `SFBFLACDecoder.seekToFrame:`
    /// обнуляет свой буфер уже ПОСЛЕ того, как libFLAC сложил туда блок с целевым
    /// сэмплом (он приходит write-колбэком во время самого seek), поэтому данные
    /// начинаются со следующей границы блока — `(⌊target/bs⌋ + 1)·bs`. Промах до
    /// целого блока: 93 мс при 4096 кадрах и 44.1 кГц, то есть у каждой дорожки
    /// CUE срезалась бы голова, а хвост залезал бы на соседнюю дорожку.
    ///
    /// Лечим у себя: целимся на блок раньше нужного и доедаем разницу декодом.
    /// У WAV (CoreAudio) seek точный — там компенсации нет, как и у FLAC с
    /// плавающим размером блока: без известного `bs` промах не посчитать.
    /// Проверяется `CueDecodeTests` — сегмент сверяется с полным декодом по битам.
    func decoder(url: URL) throws -> any PCMDecoding {
        let landing: AVAudioFramePosition
        let seekStart: AVAudioFramePosition
        if let block = Self.flacBlockSize(url: url) {
            // Первый блок seek'а не требует: свежий декодер и так стоит в нуле,
            // а `AudioRegionDecoder` не двигает то, что уже на месте.
            let index = startFrame / block
            landing = index * block
            seekStart = index == 0 ? 0 : (index - 1) * block
        } else {
            landing = startFrame
            seekStart = startFrame
        }
        let skip = startFrame - landing
        let decoder = try AudioRegionDecoder(
            url: url, startFrame: seekStart,
            frameLength: frameLength < 0 ? -1 : frameLength + skip)
        guard skip > 0 else { return decoder }
        try decoder.open()
        try Self.drop(frames: skip, from: decoder)
        return decoder
    }

    /// Размер блока FLAC из STREAMINFO; `nil` — не FLAC или блок плавающий.
    ///
    /// Раскладка фиксирована стандартом: `fLaC`, четыре байта заголовка первого
    /// метаблока, дальше STREAMINFO — минимальный и максимальный размер блока
    /// по два байта. Читаем двенадцать байт файла, без декодера.
    private static func flacBlockSize(url: URL) -> AVAudioFramePosition? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 12), head.count == 12,
            head.prefix(4).elementsEqual(Array("fLaC".utf8))
        else { return nil }
        let bytes = Array(head)
        let minimum = Int(bytes[8]) << 8 | Int(bytes[9])
        let maximum = Int(bytes[10]) << 8 | Int(bytes[11])
        guard minimum == maximum, minimum > 0 else { return nil }
        return AVAudioFramePosition(minimum)
    }

    /// Проглатывает лишние кадры между посадкой декодера и началом дорожки.
    private static func drop(frames: AVAudioFramePosition, from decoder: any PCMDecoding) throws {
        let chunk: AVAudioFrameCount = 8192
        guard
            let scratch = AVAudioPCMBuffer(
                pcmFormat: decoder.processingFormat, frameCapacity: chunk)
        else {
            throw PlaybackError.decodingFailed("cannot allocate a buffer to align a CUE segment")
        }
        var left = frames
        while left > 0 {
            try decoder.decode(into: scratch, length: AVAudioFrameCount(min(left, Int64(chunk))))
            guard scratch.frameLength > 0 else { break }
            left -= AVAudioFramePosition(scratch.frameLength)
        }
    }
}
