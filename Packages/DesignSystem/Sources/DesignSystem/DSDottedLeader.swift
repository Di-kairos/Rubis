import SwiftUI

/// Точечный лидер между названием и значением — как в трек-листе на конверте
/// пластинки (DESIGN §5.4, Jewel Box II «liner notes»).
/// Растягивается на всё свободное место строки.
public struct DSDottedLeader: View {
    public init() {}

    public var body: some View {
        LeaderLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            .foregroundStyle(DS.Color.strokeStrong)
            .frame(height: 1)
    }

    private struct LeaderLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
            return path
        }
    }
}

#Preview("Leader — light") {
    HStack(spacing: DS.Space.sm) {
        DSText("Adam's Apple", style: .headline)
        DSDottedLeader()
        DSText("6:51", style: .numeric, color: DS.Color.textTertiary)
    }
    .padding(DS.Space.xl)
    .background(DS.Color.bgBase)
    .environment(\.colorScheme, .light)
}

#Preview("Leader — dark") {
    HStack(spacing: DS.Space.sm) {
        DSText("Adam's Apple", style: .headline)
        DSDottedLeader()
        DSText("6:51", style: .numeric, color: DS.Color.textTertiary)
    }
    .padding(DS.Space.xl)
    .background(DS.Color.bgBase)
    .environment(\.colorScheme, .dark)
}
