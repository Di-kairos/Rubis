import AVFAudio
import Foundation
import SFBAudioEngine
import Synchronization

/// Декодер, заряженный на gapless, с отзывом.
///
/// Движок забирает следующий декодер из своей очереди в active, как только
/// текущий додекодирован, — задолго до того, как он дозвучал, — и `clearQueue`
/// такой декодер уже не достаёт; `nowPlaying` при этом ещё указывает на
/// текущий (F01, перепроверка аудита 13.09.2026). Публичного «убрать активный»
/// у движка нет, и доказать по его состоянию, что заряд не ушёл, нельзя.
///
/// Доказательство переносится в сам декодер: каждый `decode` идёт под замком,
/// и `revoke()` под тем же замком закрывает кран навсегда. После отзыва
/// декодер отдаёт ноль кадров — движок считает его законченным и переходит к
/// следующему в очереди, ни одного сэмпла отозванного трека наружу не уходит.
/// Возврат `revoke()` — успел ли декодер выдать хоть кадр: если да, звук уже в
/// кольцевом буфере, и честен только сброс pipeline; если нет — тишина
/// гарантирована, сброс не нужен.
final class ArmedDecoder: NSObject, PCMDecoding {
    private struct Gate {
        var revoked = false
        var produced = false
    }

    private let inner: any PCMDecoding
    private let gate = Mutex(Gate())

    init(_ inner: any PCMDecoding) {
        self.inner = inner
    }

    /// Закрывает кран. `true` — кадры уже уходили наружу.
    func revoke() -> Bool {
        gate.withLock { state in
            state.revoked = true
            return state.produced
        }
    }

    var inputSource: InputSource { inner.inputSource }
    var sourceFormat: AVAudioFormat { inner.sourceFormat }
    var processingFormat: AVAudioFormat { inner.processingFormat }
    var decodingIsLossless: Bool { inner.decodingIsLossless }
    var properties: [AudioDecodingPropertiesKey: Any] { inner.properties }
    var isOpen: Bool { inner.isOpen }
    var supportsSeeking: Bool { inner.supportsSeeking }
    var position: AVAudioFramePosition { inner.position }
    var length: AVAudioFramePosition { inner.length }

    func open() throws { if !inner.isOpen { try inner.open() } }
    func close() throws { try inner.close() }
    func seek(to frame: AVAudioFramePosition) throws { try inner.seek(to: frame) }

    func decode(into buffer: AVAudioBuffer) throws {
        guard let pcm = buffer as? AVAudioPCMBuffer else {
            try inner.decode(into: buffer)
            return
        }
        try decode(into: pcm, length: pcm.frameCapacity)
    }

    func decode(into buffer: AVAudioPCMBuffer, length frameLength: AVAudioFrameCount) throws {
        // Замок держится на всё время декода: отзыв либо опережает кадры, либо
        // видит, что они уже были. Третьего — «отозвали, а кадры всё же ушли» —
        // не бывает. Это decoding thread движка, не render thread.
        try gate.withLock { state in
            guard !state.revoked else {
                buffer.frameLength = 0
                return
            }
            try inner.decode(into: buffer, length: frameLength)
            if buffer.frameLength > 0 { state.produced = true }
        }
    }
}
