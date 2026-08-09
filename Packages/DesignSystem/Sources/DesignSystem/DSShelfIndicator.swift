import SwiftUI

/// Указатель прокрутки полки (DESIGN §5.3): вместо системного скроллбара —
/// волосяная направляющая и золотой ползунок, у которого на обоих концах
/// рубиновые ◆ (токен `gem`, D-007). Ромбы едут вместе с ползунком — это
/// его «оправа», а не украшение шкалы.
public struct DSShelfIndicator: View {
    private let progress: Double
    private let visible: Double
    /// Указатель не только показывает, но и ведёт: тянешь — полка едет.
    private let onScrub: ((Double) -> Void)?

    public init(progress: Double, visible: Double, onScrub: ((Double) -> Void)? = nil) {
        self.progress = progress.isFinite ? min(max(progress, 0), 1) : 0
        self.visible = visible.isFinite ? min(max(visible, 0), 1) : 1
        self.onScrub = onScrub
    }

    public var body: some View {
        GeometryReader { geo in
            canvas
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in scrub(x: value.location.x, width: geo.size.width) }
                        .onEnded { value in scrub(x: value.location.x, width: geo.size.width) }
                )
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    /// Тяга за ползунок: центр ползунка едет к курсору, края зажаты.
    private func scrub(x: CGFloat, width: CGFloat) {
        let capInset: CGFloat = 10
        let railWidth = width - capInset * 2
        let thumbWidth = max(36, railWidth * visible)
        let travel = railWidth - thumbWidth
        guard travel > 0 else { return }
        let position = x - capInset - thumbWidth / 2
        onScrub?(min(max(Double(position / travel), 0), 1))
    }

    private var canvas: some View {
        Canvas { context, size in
            let capInset: CGFloat = 10
            let midY = size.height / 2
            let railStart = capInset
            let railEnd = size.width - capInset
            guard railEnd > railStart else { return }

            var rail = Path()
            rail.move(to: CGPoint(x: railStart, y: midY))
            rail.addLine(to: CGPoint(x: railEnd, y: midY))
            context.stroke(rail, with: .color(DS.Color.strokeHairline), lineWidth: 1)

            // Ползунок: доля видимой части полки, минимум — чтобы не исчезал.
            let railWidth = railEnd - railStart
            let thumbWidth = max(36, railWidth * visible)
            let thumbX = railStart + (railWidth - thumbWidth) * progress
            let thumb = Path(
                roundedRect: CGRect(x: thumbX, y: midY - 1.5, width: thumbWidth, height: 3),
                cornerRadius: 1.5)
            context.fill(thumb, with: .color(DS.Color.accent))

            // Рубиновая оправа ползунка — едет вместе с ним.
            context.fill(
                diamond(center: CGPoint(x: thumbX, y: midY), radius: 3.5),
                with: .color(DS.Color.gem))
            context.fill(
                diamond(center: CGPoint(x: thumbX + thumbWidth, y: midY), radius: 3.5),
                with: .color(DS.Color.gem))
        }
    }

    private func diamond(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.closeSubpath()
        return path
    }
}

#Preview("DSShelfIndicator — dark") {
    VStack(spacing: DS.Space.lg) {
        DSShelfIndicator(progress: 0, visible: 0.4)
        DSShelfIndicator(progress: 0.5, visible: 0.4)
        DSShelfIndicator(progress: 1, visible: 0.4)
    }
    .padding(DS.Space.xl)
    .frame(width: 420)
    .background(DS.Color.bgBase)
    .preferredColorScheme(.dark)
}

#Preview("DSShelfIndicator — light") {
    VStack(spacing: DS.Space.lg) {
        DSShelfIndicator(progress: 0, visible: 0.4)
        DSShelfIndicator(progress: 0.5, visible: 0.4)
        DSShelfIndicator(progress: 1, visible: 0.4)
    }
    .padding(DS.Space.xl)
    .frame(width: 420)
    .background(DS.Color.bgBase)
    .preferredColorScheme(.light)
}
