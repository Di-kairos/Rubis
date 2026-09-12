import EscapementCore
import Foundation

/// Audio-path settings consumed by the engine (SPEC §4.2, §8 Audio tab).
/// Persisted by the app layer; the engine only reads values.
public struct AudioConfiguration: Sendable, Equatable {
    /// Hog the device while playing (SPEC §4.2.1). Default on.
    public var exclusiveAccess: Bool
    /// Pause inserted when the device sample rate actually changes (SPEC §4.2.4).
    public var sampleRateChangeDelay: Duration
    /// What to do when the device lacks the exact source rate (SPEC §4.2.3).
    public var rateFallback: SampleRatePolicy.FallbackBehavior
    /// DSD handling (SPEC §4.2.6).
    public var dsdMode: DSDMode
    /// Устройства (по UID), про которые владелец подтвердил: этот ЦАП разбирает
    /// DoP-маркеры. HAL не умеет об этом спросить — PCM-частота 176.4 кГц
    /// доказывает только транспорт, и ЦАП без DoP сыграл бы пакеты шумом.
    /// Без подтверждения DSD идёт через PCM-конверсию.
    public var dopConfirmedDeviceUIDs: Set<String>
    /// Explicit output device UID; nil follows the system default output.
    public var preferredDeviceUID: String?

    public init(
        exclusiveAccess: Bool = true,
        sampleRateChangeDelay: Duration = .milliseconds(300),
        rateFallback: SampleRatePolicy.FallbackBehavior = .nearestFamilyMultiple,
        dsdMode: DSDMode = .dopIfAvailable,
        dopConfirmedDeviceUIDs: Set<String> = [],
        preferredDeviceUID: String? = nil
    ) {
        self.exclusiveAccess = exclusiveAccess
        self.sampleRateChangeDelay = sampleRateChangeDelay
        self.rateFallback = rateFallback
        self.dsdMode = dsdMode
        self.dopConfirmedDeviceUIDs = dopConfirmedDeviceUIDs
        self.preferredDeviceUID = preferredDeviceUID
    }
}
