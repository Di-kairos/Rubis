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
    /// Та же компенсация нужна и КАЖДОМУ seek внутри дорожки: сдвиг аргумента
    /// оставлял часы верными, а сэмплы — от следующей границы блока (R04,
    /// перепроверка аудита 13.09.2026). У WAV (CoreAudio) seek точный — там
    /// компенсации нет, как и у FLAC с плавающим размером блока: без известного
    /// `bs` промах не посчитать. Побитовую сверку с полным декодом держат
    /// `CueDecodeTests` и `ReauditRegressionTests`.
    func decoder(url: URL) throws -> any PCMDecoding {
        guard let block = Self.flacBlockSize(url: url) else {
            return try AudioRegionDecoder(
                url: url, startFrame: startFrame, frameLength: frameLength)
        }
        let landed = try Self.land(region: self, url: url, block: block, at: 0)
        return AlignedRegionDecoder(region: self, url: url, block: block, inner: landed.decoder)
    }

    /// Готовый к чтению декодер, стоящий ровно на `offset` кадрах от начала дорожки.
    ///
    /// Посадка FLAC всегда на блок позже запрошенного, поэтому просим на блок
    /// раньше цели и доедаем разницу. Декодер возвращается открытым.
    fileprivate static func land(
        region: CueRegion, url: URL, block: AVAudioFramePosition, at offset: AVAudioFramePosition
    ) throws -> (decoder: AudioRegionDecoder, skip: AVAudioFramePosition) {
        let target = region.startFrame + offset
        let index = target / block
        let landing = index * block
        // Первый блок seek'а не требует: свежий декодер и так стоит в нуле,
        // а `AudioRegionDecoder` не двигает то, что уже на месте.
        let seekStart = index == 0 ? 0 : (index - 1) * block
        let skip = target - landing
        let remaining = region.frameLength < 0 ? -1 : max(0, region.frameLength - offset)
        let decoder = try AudioRegionDecoder(
            url: url, startFrame: seekStart,
            frameLength: remaining < 0 ? -1 : remaining + skip)
        try decoder.open()
        if skip > 0 { try drop(frames: skip, from: decoder) }
        return (decoder, skip)
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
    fileprivate static func drop(frames: AVAudioFramePosition, from decoder: any PCMDecoding) throws
    {
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

/// Декодер сегмента с часами самой дорожки. `AudioRegionDecoder` после
/// компенсации FLAC-посадки стоит на `skip` кадрах и считает длину от
/// посадки: позиция начиналась бы с ~50–90 мс, длительность была бы длиннее
/// на столько же, а `seek(0)` уезжал бы в предыдущую дорожку.
///
/// Перемотка пересобирает внутренний декодер тем же путём, что и старт:
/// сдвинуть аргумент мало — посадка FLAC промахивается на блок при каждом
/// seek, и после него шли чужие сэмплы при верных часах (R04).
final class AlignedRegionDecoder: NSObject, PCMDecoding {
    private let region: CueRegion
    private let url: URL
    private let block: AVAudioFramePosition
    private var inner: AudioRegionDecoder
    /// Часы дорожки в точке, с которой начал текущий внутренний декодер.
    private var origin: AVAudioFramePosition = 0
    /// Кадры, выданные наружу после последней посадки. Позицию считаем сами:
    /// `AudioRegionDecoder` на исчерпанном регионе засчитывает остаток дважды
    /// (замер: skip 4912 → position 9824), и часы дорожки уезжали за её конец.
    private var delivered: AVAudioFramePosition = 0

    init(region: CueRegion, url: URL, block: AVAudioFramePosition, inner: AudioRegionDecoder) {
        self.region = region
        self.url = url
        self.block = block
        self.inner = inner
    }

    var inputSource: InputSource { inner.inputSource }
    var sourceFormat: AVAudioFormat { inner.sourceFormat }
    var processingFormat: AVAudioFormat { inner.processingFormat }
    var decodingIsLossless: Bool { inner.decodingIsLossless }
    var properties: [AudioDecodingPropertiesKey: Any] { inner.properties }
    var isOpen: Bool { inner.isOpen }
    var supportsSeeking: Bool { inner.supportsSeeking }

    func open() throws { if !inner.isOpen { try inner.open() } }
    func close() throws { try inner.close() }

    /// Часы дорожки: сколько кадров дорожки уже отдано.
    var position: AVAudioFramePosition { origin + delivered }
    /// Длина самой дорожки, а не остатка после последней перемотки.
    var length: AVAudioFramePosition { region.frameLength }

    func decode(into buffer: AVAudioBuffer) throws {
        try inner.decode(into: buffer)
        if let pcm = buffer as? AVAudioPCMBuffer {
            delivered += AVAudioFramePosition(pcm.frameLength)
        }
    }

    func decode(into buffer: AVAudioPCMBuffer, length frameLength: AVAudioFrameCount) throws {
        try inner.decode(into: buffer, length: frameLength)
        delivered += AVAudioFramePosition(buffer.frameLength)
    }

    func seek(to frame: AVAudioFramePosition) throws {
        let ceiling = region.frameLength < 0 ? frame : min(frame, region.frameLength)
        let offset = max(0, ceiling)
        let landed = try CueRegion.land(region: region, url: url, block: block, at: offset)
        try? inner.close()
        inner = landed.decoder
        origin = offset
        delivered = 0
    }
}
