import SwiftUI

/// Playback progress bar (DESIGN.md §5.1): 3 pt tall, 5 pt on hover,
/// handle appears only on hover, linear motion, accent fill, no glow.
public struct DSProgressBar: View {
    private let progress: Double
    private let onSeek: ((Double) -> Void)?

    @State private var hovering = false
    @Environment(\.controlActiveState) private var activeState

    public init(progress: Double, onSeek: ((Double) -> Void)? = nil) {
        self.progress = progress.isFinite ? min(max(progress, 0), 1) : 0
        self.onSeek = onSeek
    }

    public var body: some View {
        GeometryReader { geo in
            let height = hovering ? DS.Metrics.progressBarHeightHover : DS.Metrics.progressBarHeight
            let fillWidth = geo.size.width * progress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.Color.strokeStrong)
                    .frame(height: height)
                Capsule()
                    .fill(accentColor)
                    .frame(width: fillWidth, height: height)
                if hovering {
                    Circle()
                        .fill(DS.Color.textPrimary)
                        .frame(width: 9, height: 9)
                        .offset(x: fillWidth - 4.5)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        onSeek?(min(max(value.location.x / geo.size.width, 0), 1))
                    }
            )
        }
        .frame(height: DS.Metrics.progressBarHeightHover + DS.Space.sm)
        .onHover { hovering = $0 }
        .animation(DS.Motion.hover, value: hovering)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }

    /// Muted accent when the window is inactive (DESIGN.md §2.1).
    private var accentColor: SwiftUI.Color {
        activeState == .inactive ? DS.Color.accentMuted : DS.Color.accent
    }
}

#Preview("DSProgressBar — dark") {
    DSProgressBar(progress: 0.32)
        .padding(DS.Space.xl)
        .frame(width: 420)
        .background(DS.Color.bgRaised)
        .preferredColorScheme(.dark)
}

#Preview("DSProgressBar — light") {
    DSProgressBar(progress: 0.32)
        .padding(DS.Space.xl)
        .frame(width: 420)
        .background(DS.Color.bgRaised)
        .preferredColorScheme(.light)
}
