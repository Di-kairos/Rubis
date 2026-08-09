import SwiftUI

/// Указатель прокрутки (DESIGN §5.3): вместо системного скроллбара —
/// волосяная направляющая и золотой ползунок, у которого на обоих концах
/// рубиновые ◆ (токен `gem`, D-007). Ромбы едут вместе с ползунком — это
/// его «оправа», а не украшение шкалы. Один язык для полки альбомов
/// (горизонтальный) и списков (вертикальный).
public struct DSScrollIndicator: View {
    private let axis: Axis
    private let progress: Double
    private let visible: Double
    /// Указатель не только показывает, но и ведёт: тянешь — список едет.
    private let onScrub: ((Double) -> Void)?

    /// Толщина полосы: столько же занимает системный скроллбар, не больше.
    public static let thickness: CGFloat = 14

    public init(
        axis: Axis = .horizontal,
        progress: Double,
        visible: Double,
        onScrub: ((Double) -> Void)? = nil
    ) {
        self.axis = axis
        self.progress = progress.isFinite ? min(max(progress, 0), 1) : 0
        self.visible = visible.isFinite ? min(max(visible, 0), 1) : 1
        self.onScrub = onScrub
    }

    public var body: some View {
        GeometryReader { geo in
            let length = axis == .horizontal ? geo.size.width : geo.size.height
            canvas
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrub(
                                at: axis == .horizontal ? value.location.x : value.location.y,
                                length: length)
                        }
                        .onEnded { value in
                            scrub(
                                at: axis == .horizontal ? value.location.x : value.location.y,
                                length: length)
                        }
                )
        }
        .frame(
            width: axis == .vertical ? Self.thickness : nil,
            height: axis == .horizontal ? Self.thickness : nil
        )
        .accessibilityHidden(true)
    }

    /// Тяга за ползунок: его центр едет к курсору, края зажаты.
    private func scrub(at position: CGFloat, length: CGFloat) {
        let rail = length - Self.capInset * 2
        let thumb = max(Self.minThumb, rail * visible)
        let travel = rail - thumb
        guard travel > 0 else { return }
        let shifted = position - Self.capInset - thumb / 2
        onScrub?(min(max(Double(shifted / travel), 0), 1))
    }

    private static let capInset: CGFloat = 10
    private static let minThumb: CGFloat = 36

    private var canvas: some View {
        Canvas { context, size in
            let length = axis == .horizontal ? size.width : size.height
            let cross = (axis == .horizontal ? size.height : size.width) / 2
            let railStart = Self.capInset
            let railEnd = length - Self.capInset
            guard railEnd > railStart else { return }

            var rail = Path()
            rail.move(to: point(along: railStart, cross: cross))
            rail.addLine(to: point(along: railEnd, cross: cross))
            context.stroke(rail, with: .color(DS.Color.strokeHairline), lineWidth: 1)

            // Ползунок: доля видимой части, минимум — чтобы не исчезал.
            let railLength = railEnd - railStart
            let thumbLength = max(Self.minThumb, railLength * visible)
            let thumbStart = railStart + (railLength - thumbLength) * progress
            let box =
                axis == .horizontal
                ? CGRect(x: thumbStart, y: cross - 1.5, width: thumbLength, height: 3)
                : CGRect(x: cross - 1.5, y: thumbStart, width: 3, height: thumbLength)
            context.fill(Path(roundedRect: box, cornerRadius: 1.5), with: .color(DS.Color.accent))

            // Рубиновая оправа ползунка — едет вместе с ним.
            context.fill(
                diamond(center: point(along: thumbStart, cross: cross), radius: 3.5),
                with: .color(DS.Color.gem))
            context.fill(
                diamond(center: point(along: thumbStart + thumbLength, cross: cross), radius: 3.5),
                with: .color(DS.Color.gem))
        }
    }

    /// Точка «вдоль оси / поперёк оси» → экранные координаты.
    private func point(along: CGFloat, cross: CGFloat) -> CGPoint {
        axis == .horizontal ? CGPoint(x: along, y: cross) : CGPoint(x: cross, y: along)
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

#Preview("DSScrollIndicator — dark") {
    HStack(spacing: DS.Space.xl) {
        VStack(spacing: DS.Space.lg) {
            DSScrollIndicator(progress: 0, visible: 0.4)
            DSScrollIndicator(progress: 0.5, visible: 0.4)
            DSScrollIndicator(progress: 1, visible: 0.4)
        }
        DSScrollIndicator(axis: .vertical, progress: 0.35, visible: 0.3)
            .frame(height: 160)
    }
    .padding(DS.Space.xl)
    .frame(width: 420)
    .background(DS.Color.bgBase)
    .preferredColorScheme(.dark)
}

#Preview("DSScrollIndicator — light") {
    HStack(spacing: DS.Space.xl) {
        VStack(spacing: DS.Space.lg) {
            DSScrollIndicator(progress: 0, visible: 0.4)
            DSScrollIndicator(progress: 0.5, visible: 0.4)
            DSScrollIndicator(progress: 1, visible: 0.4)
        }
        DSScrollIndicator(axis: .vertical, progress: 0.35, visible: 0.3)
            .frame(height: 160)
    }
    .padding(DS.Space.xl)
    .frame(width: 420)
    .background(DS.Color.bgBase)
    .preferredColorScheme(.light)
}
