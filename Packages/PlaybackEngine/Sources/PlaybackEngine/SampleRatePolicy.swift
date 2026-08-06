import Foundation

/// Pure sample-rate selection logic (SPEC §4.2.3). No hardware here —
/// fully unit-testable. The engine applies the decision to the device.
public enum SampleRatePolicy {
    /// What to do when the device cannot match the source rate exactly.
    public enum FallbackBehavior: String, Codable, Sendable {
        /// Pick a same-family multiple, mark as resampling (default).
        case nearestFamilyMultiple
        /// Additionally allow 44.1↔48 family switch (explicit user opt-in).
        case allowCrossFamily
        /// Refuse to play.
        case refuse
    }

    public enum Decision: Equatable, Sendable {
        /// Device set to the exact source rate — bit-perfect preserved.
        case exact(Double)
        /// Same-family multiple — resampling, UI shows "192 → 96" in warning color.
        case familyMultiple(Double)
        /// Cross-family rate — resampling, allowed only by explicit setting.
        case crossFamily(Double)
        /// No acceptable rate; do not start playback.
        case refuse
    }

    static let family44 = [44100.0, 88200.0, 176400.0, 352800.0]
    static let family48 = [48000.0, 96000.0, 192000.0, 384000.0]

    /// Chooses the device rate for a source rate given the device's supported set.
    public static func choose(
        source: Double,
        available: [Double],
        fallback: FallbackBehavior
    ) -> Decision {
        guard !available.isEmpty else { return .refuse }
        if available.contains(source) {
            return .exact(source)
        }

        switch fallback {
        case .refuse:
            return .refuse
        case .nearestFamilyMultiple, .allowCrossFamily:
            if let familyRate = bestFamilyRate(source: source, available: available) {
                return .familyMultiple(familyRate)
            }
            guard fallback == .allowCrossFamily else { return .refuse }
            // Cross-family: highest available rate minimizes resampler damage.
            if let best = available.max() {
                return .crossFamily(best)
            }
            return .refuse
        }
    }

    /// Same-family fallback: prefer the smallest supported multiple above the
    /// source (clean integer upsample), else the largest supported below it.
    private static func bestFamilyRate(source: Double, available: [Double]) -> Double? {
        let family =
            family44.contains(source) ? family44 : family48.contains(source) ? family48 : []
        guard !family.isEmpty else { return nil }
        let supported = family.filter { available.contains($0) }
        if let above = supported.filter({ $0 > source }).min() {
            return above
        }
        return supported.filter { $0 < source }.max()
    }
}
