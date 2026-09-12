import Foundation

/// Playback state machine (SPEC §4.5).
public enum PlaybackState: Sendable, Equatable {
    case idle
    case loading(Track)
    case playing(Track)
    case paused(Track)
    case failed(Track, PlaybackError)
}

public enum PlaybackError: Error, Sendable, Equatable, LocalizedError {
    case fileNotFound(String)
    case decodingFailed(String)
    case deviceUnavailable
    case deviceLost
    /// «Bit-perfect или тишина»: устройство не умеет частоту записи, а политика
    /// `rateFallback = .refuse` запрещает ресемплинг. Отказ намеренный —
    /// в строке состояния он обязан читаться как решение, а не как поломка.
    case rateRefused(source: Double, device: String)

    /// Текст для строки состояния — то, что владелец видит вместо кода ошибки.
    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File is missing"
        case .decodingFailed(let reason):
            return "Cannot decode this file — \(reason)"
        case .deviceUnavailable:
            return "Output device is unavailable — pick another in Settings → Audio"
        case .deviceLost:
            return "Output device disappeared"
        case .rateRefused(let source, let device):
            // Частота — приборное число: точка, а не запятая локали.
            let khz = String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), source / 1000)
            return "Refused: \(device) cannot do \(khz) kHz, and resampling is off"
        }
    }
}

/// DSD output mode (SPEC §4.2.6).
public enum DSDMode: String, Codable, Sendable {
    case dopIfAvailable
    case alwaysConvertToPCM
}

/// Как DSD на самом деле покинул приложение — применённый путь, а не
/// пожелание из настроек.
public enum DSDPath: String, Codable, Sendable {
    /// DSD-пакеты внутри 24-битных PCM-кадров; ЦАП разбирает маркеры сам.
    case dop
    /// Преобразование в PCM внутри приложения.
    case pcmConversion
}

/// Signal-path status feeding the UI badge (SPEC §4.5).
///
/// Снимок применённого тракта: параметры источника — из открытого декодера,
/// параметры устройства — из результата настройки HAL. Неизвестное остаётся
/// неизвестным (`nil`), а не подменяется правдоподобным числом.
/// `isBitPerfect` never lies upward: any doubt reads as false.
public struct OutputStatus: Sendable, Equatable {
    public let deviceName: String
    public let deviceUID: String
    public let deviceSampleRate: Double
    public let sourceSampleRate: Double
    /// nil — декодер разрядность не сообщает.
    public let sourceBitDepth: Int?
    public let sourceChannels: Int
    public let isExclusive: Bool
    /// nil — микшер не трогали (выход общий или устройство не даёт ручки);
    /// false — пытались снять, устройство отказало.
    public let mixingDisabled: Bool?
    public let dsdPath: DSDPath?
    /// Политика частоты, действовавшая при настройке устройства — настройки
    /// могли поменяться после старта, отчёт описывает то, что применено.
    public let ratePolicy: String
    public let isBitPerfect: Bool

    public init(
        deviceName: String,
        deviceUID: String,
        deviceSampleRate: Double,
        sourceSampleRate: Double,
        sourceBitDepth: Int?,
        sourceChannels: Int,
        isExclusive: Bool,
        mixingDisabled: Bool?,
        dsdPath: DSDPath? = nil,
        ratePolicy: String,
        isBitPerfect: Bool
    ) {
        self.deviceName = deviceName
        self.deviceUID = deviceUID
        self.deviceSampleRate = deviceSampleRate
        self.sourceSampleRate = sourceSampleRate
        self.sourceBitDepth = sourceBitDepth
        self.sourceChannels = sourceChannels
        self.isExclusive = isExclusive
        self.mixingDisabled = mixingDisabled
        self.dsdPath = dsdPath
        self.ratePolicy = ratePolicy
        self.isBitPerfect = isBitPerfect
    }

    /// Тот же тракт с другим источником — переход gapless меняет файл, но не
    /// устройство. Bit-perfect пересчитывается: точность частоты у нового
    /// файла та же (склейка идёт только при равной частоте), остальное — тоже.
    public func withSource(sampleRate: Double, bitDepth: Int?, channels: Int) -> OutputStatus {
        OutputStatus(
            deviceName: deviceName, deviceUID: deviceUID, deviceSampleRate: deviceSampleRate,
            sourceSampleRate: sampleRate, sourceBitDepth: bitDepth, sourceChannels: channels,
            isExclusive: isExclusive, mixingDisabled: mixingDisabled, dsdPath: dsdPath,
            ratePolicy: ratePolicy, isBitPerfect: isBitPerfect && sampleRate == sourceSampleRate)
    }
}
