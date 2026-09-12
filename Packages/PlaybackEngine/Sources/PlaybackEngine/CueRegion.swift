import AVFAudio
import EscapementCore
import Foundation

/// Границы дорожки CUE в кадрах — то, чем регион задаётся декодеру (D-013).
///
/// Секунды из листа считаются в кадры по частоте самого файла: CUE меряет
/// время кадрами CD (1/75 с) независимо от того, что внутри 44.1 или 96 кГц,
/// и округление до кадра файла — единственное честное преобразование.
struct CueRegion: Equatable {
    let startFrame: AVAudioFramePosition
    /// −1 — «до конца файла»: у последней дорожки листа конца нет.
    let frameLength: AVAudioFramePosition

    /// Секунды, дальше которых лист не читаем: произведение на частоту обязано
    /// помещаться в `Int64`, иначе преобразование ниже — аварийное завершение,
    /// а не ошибка. Парсер CUE держит тот же предел, но строка в базе могла
    /// прийти из прежней версии — защита здесь независимая.
    static let maxSeconds: Double = 1e9

    /// `nil` — границ нет, файл играет целиком: не только у трека без листа,
    /// но и у листа с неконечным или невозможным временем.
    init?(track: Track) {
        guard let start = track.cueStart, track.sampleRate > 0,
            start.isFinite, start < Self.maxSeconds
        else { return nil }
        let rate = Double(track.sampleRate)
        startFrame = AVAudioFramePosition((max(0, start) * rate).rounded())
        guard let end = track.cueEnd, end.isFinite, end < Self.maxSeconds else {
            frameLength = -1
            return
        }
        // Конец раньше начала — лист врёт; играем до конца файла, а не
        // отдаём декодеру отрицательную длину.
        let frames = AVAudioFramePosition(((end - start) * rate).rounded())
        frameLength = frames > 0 ? frames : -1
    }
}
