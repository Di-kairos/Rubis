import SwiftUI

/// Signal-path quality badge (SPEC §7.3, DESIGN.md §5.1). The only honest
/// indicator of the bit-perfect contract — color follows output status.
public struct DSTechBadge: View {
    /// Mirrors OutputStatus.isBitPerfect plus its failure reasons.
    public enum Status {
        /// Exclusive access, rates match, no DSP — accent color.
        case bitPerfect
        /// Hog mode lost or software path — muted color.
        case degraded
        /// Resampling in effect — warning color.
        case resampling
    }

    private let segments: [String]
    private let status: Status

    @Environment(\.controlActiveState) private var activeState

    public init(segments: [String], status: Status) {
        self.segments = segments
        self.status = status
    }

    public var body: some View {
        DSText(segments.joined(separator: "  ·  "), style: .caption, color: color)
            .accessibilityLabel("Output status: \(segments.joined(separator: ", "))")
    }

    private var color: SwiftUI.Color {
        switch status {
        case .bitPerfect:
            return activeState == .inactive ? DS.Color.accentMuted : DS.Color.accent
        case .degraded:
            return DS.Color.textSecondary
        case .resampling:
            return DS.Color.warning
        }
    }
}

#Preview("DSTechBadge — dark") {
    VStack(alignment: .trailing, spacing: DS.Space.sm) {
        DSTechBadge(segments: ["FLAC 24/192", "Exclusive", "RME ADI-2"], status: .bitPerfect)
        DSTechBadge(segments: ["FLAC 24/192", "Shared", "MacBook Pro Speakers"], status: .degraded)
        DSTechBadge(segments: ["192 → 96", "Exclusive", "RME ADI-2"], status: .resampling)
    }
    .padding(DS.Space.xl)
    .background(DS.Color.bgRaised)
    .preferredColorScheme(.dark)
}

#Preview("DSTechBadge — light") {
    VStack(alignment: .trailing, spacing: DS.Space.sm) {
        DSTechBadge(segments: ["FLAC 24/192", "Exclusive", "RME ADI-2"], status: .bitPerfect)
        DSTechBadge(segments: ["192 → 96", "Exclusive", "RME ADI-2"], status: .resampling)
    }
    .padding(DS.Space.xl)
    .background(DS.Color.bgRaised)
    .preferredColorScheme(.light)
}
