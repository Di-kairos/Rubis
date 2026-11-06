import CoreAudio
import Synchronization

/// Устройство, на котором движок обязан стоять.
///
/// AVAudioEngine на macOS идёт за системным выходом по умолчанию даже после
/// явного `setDeviceID`: сменился default — движок уже там (проверено на FiiO
/// QX13 и BlackHole, S23). А hog сам сдвигает default: CoreAudio уводит его с
/// захваченного ЦАПа на динамики. Без закрепления плеер держал ЦАП в hog,
/// бейдж писал «EXCLUSIVE · FIIO», а звук шёл из ноутбука.
///
/// Читается из колбэка смены конфигурации на внутренней очереди AVAudioEngine,
/// пишется актором `Player` — отсюда замок.
final class OutputPin: Sendable {
    private let device = Mutex<AudioObjectID?>(nil)

    func set(_ id: AudioObjectID?) { device.withLock { $0 = id } }

    /// Куда вернуть движок, если он ушёл с закреплённого устройства.
    func drift(from engineDevice: AudioObjectID) -> AudioObjectID? {
        guard let pinned = device.withLock({ $0 }), pinned != engineDevice else { return nil }
        return pinned
    }
}
