import Foundation

/// Playback state machine (SPEC §4.5).
public enum PlaybackState: Sendable, Equatable {
    case idle
    case loading(Track)
    case playing(Track)
    case paused(Track)
    case failed(Track, PlaybackError)
}

public enum PlaybackError: Error, Sendable, Equatable {
    case fileNotFound(String)
    case decodingFailed(String)
    case deviceUnavailable
    case deviceLost
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
