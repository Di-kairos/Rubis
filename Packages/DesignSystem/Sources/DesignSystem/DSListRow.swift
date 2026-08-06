import SwiftUI

/// List row container: hover and selection backgrounds, no separators,
/// square corners (DESIGN.md §5.2). Content decides its own columns.
public struct DSListRow<Content: View>: View {
    private let isSelected: Bool
    private let height: CGFloat
    private let content: Content

    @State private var hovering = false

    public init(
        isSelected: Bool = false,
        height: CGFloat = DS.Metrics.trackRowCompact,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.height = height
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            .padding(.horizontal, DS.Space.md)
            .background(background)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(DS.Motion.hover, value: hovering)
    }

    private var background: SwiftUI.Color {
        if isSelected { return DS.Color.bgSelected }
        if hovering { return DS.Color.bgHover }
        return .clear
    }
}

#Preview("DSListRow — dark") {
    VStack(spacing: 0) {
        DSListRow {
            HStack {
                DSText("3", style: .numeric, color: DS.Color.textTertiary)
                DSText("Blue in Green", style: .headline)
                Spacer()
                DSText("5:37", style: .numeric, color: DS.Color.textTertiary)
            }
        }
        DSListRow(isSelected: true) {
            HStack {
                DSText("4", style: .numeric, color: DS.Color.textTertiary)
                DSText("All Blues", style: .headline, color: DS.Color.accent)
                Spacer()
                DSText("11:33", style: .numeric, color: DS.Color.textTertiary)
            }
        }
    }
    .frame(width: 420)
    .background(DS.Color.bgBase)
    .preferredColorScheme(.dark)
}

#Preview("DSListRow — light") {
    VStack(spacing: 0) {
        DSListRow {
            HStack {
                DSText("3", style: .numeric, color: DS.Color.textTertiary)
                DSText("Blue in Green", style: .headline)
                Spacer()
                DSText("5:37", style: .numeric, color: DS.Color.textTertiary)
            }
        }
        DSListRow(isSelected: true) {
            HStack {
                DSText("4", style: .numeric, color: DS.Color.textTertiary)
                DSText("All Blues", style: .headline, color: DS.Color.accent)
                Spacer()
                DSText("11:33", style: .numeric, color: DS.Color.textTertiary)
            }
        }
    }
    .frame(width: 420)
    .background(DS.Color.bgBase)
    .preferredColorScheme(.light)
}
