import SwiftUI

/// Шкала-линейка воспроизведения (DESIGN §5.1, Jewel Box II «Прибор»):
/// риски как на измерительном приборе, золотое заполнение и игла позиции —
/// вместо системного слайдера. Движение строго линейное (DESIGN §6).
public struct DSRulerScale: View {
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
            Canvas { context, size in
                let baseline = size.height - 7
                let fillX = size.width * progress

                // Риски: шаг 8 pt, каждая пятая длинная. Рисуются одним Canvas —
                // без пер-элементных вью, чтобы 10-Гц тик не стоил layout.
                var minor = Path()
                var major = Path()
                var x: CGFloat = 0
                var index = 0
                while x <= size.width {
                    let height: CGFloat = index.isMultiple(of: 5) ? 10 : 6
                    if index.isMultiple(of: 5) {
                        major.move(to: CGPoint(x: x, y: baseline - height))
                        major.addLine(to: CGPoint(x: x, y: baseline - 2))
                    } else {
                        minor.move(to: CGPoint(x: x, y: baseline - height))
                        minor.addLine(to: CGPoint(x: x, y: baseline - 2))
                    }
                    x += 8
                    index += 1
                }
                context.stroke(minor, with: .color(DS.Color.strokeHairline), lineWidth: 1)
                context.stroke(major, with: .color(DS.Color.strokeStrong), lineWidth: 1)

                // Полотно шкалы и золотая пройденная часть.
                var track = Path()
                track.move(to: CGPoint(x: 0, y: baseline))
                track.addLine(to: CGPoint(x: size.width, y: baseline))
                context.stroke(track, with: .color(DS.Color.strokeStrong), lineWidth: 2)

                var fill = Path()
                fill.move(to: CGPoint(x: 0, y: baseline))
                fill.addLine(to: CGPoint(x: fillX, y: baseline))
                context.stroke(fill, with: .color(accentColor), lineWidth: 2)

                // Игла позиции: тонкая, выше рисок — читается издалека.
                var needle = Path()
                needle.move(to: CGPoint(x: fillX, y: baseline - 14))
                needle.addLine(to: CGPoint(x: fillX, y: baseline + 3))
                context.stroke(needle, with: .color(accentColor), lineWidth: 1.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        onSeek?(min(max(value.location.x / geo.size.width, 0), 1))
                    }
            )
        }
        .frame(height: 26)
        .onHover { hovering = $0 }
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }

    /// Muted accent when the window is inactive (DESIGN.md §2.1).
    private var accentColor: SwiftUI.Color {
        activeState == .inactive ? DS.Color.accentMuted : DS.Color.accent
    }
}

#Preview("DSRulerScale — dark") {
    DSRulerScale(progress: 0.38)
        .padding(DS.Space.xl)
        .frame(width: 460)
        .background(DS.Color.bgRaised)
        .preferredColorScheme(.dark)
}

#Preview("DSRulerScale — light") {
    DSRulerScale(progress: 0.38)
        .padding(DS.Space.xl)
        .frame(width: 460)
        .background(DS.Color.bgRaised)
        .preferredColorScheme(.light)
}
