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

/// Signal-path status feeding the UI badge (SPEC §4.5).
/// `isBitPerfect` never lies upward: any doubt reads as false.
public struct OutputStatus: Sendable, Equatable {
    public let deviceName: String
    public let deviceSampleRate: Double
    public let sourceSampleRate: Double
    public let sourceBitDepth: Int
    public let isExclusive: Bool
    public let isBitPerfect: Bool
    public let dsdMode: DSDMode?

    public init(
        deviceName: String,
        deviceSampleRate: Double,
        sourceSampleRate: Double,
        sourceBitDepth: Int,
        isExclusive: Bool,
        isBitPerfect: Bool,
        dsdMode: DSDMode? = nil
    ) {
        self.deviceName = deviceName
        self.deviceSampleRate = deviceSampleRate
        self.sourceSampleRate = sourceSampleRate
        self.sourceBitDepth = sourceBitDepth
        self.isExclusive = isExclusive
        self.isBitPerfect = isBitPerfect
        self.dsdMode = dsdMode
    }
}
