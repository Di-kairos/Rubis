import SwiftUI

/// Styled text primitive. The only way text should appear in the app —
/// applies font, tracking and casing rules from DESIGN.md §3 per style.
public struct DSText: View {
    public enum Style {
        case display
        case title
        case headline
        case body
        case caption
        case label
        case numeric
    }

    private let text: String
    private let style: Style
    private let color: SwiftUI.Color

    public init(_ text: String, style: Style = .body, color: SwiftUI.Color = DS.Color.textPrimary) {
        self.text = text
        self.style = style
        self.color = color
    }

    @Environment(\.colorSchemeContrast) private var contrast

    public var body: some View {
        content
            .foregroundStyle(DS.Contrast.text(color, increased: contrast == .increased))
            .truncationMode(.tail)
            .lineLimit(1)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .display:
            Text(text).font(DS.Font.display).tracking(DS.Font.Tracking.display)
        case .title:
            Text(text).font(DS.Font.title)
        case .headline:
            Text(text).font(DS.Font.headline)
        case .body:
            Text(text).font(DS.Font.body)
        case .caption:
            Text(text).font(DS.Font.caption).tracking(DS.Font.Tracking.caption)
        case .label:
            Text(text.uppercased()).font(DS.Font.label).tracking(DS.Font.Tracking.label)
        case .numeric:
            Text(text).font(DS.Font.numeric)
        }
    }
}

#Preview("DSText — dark") {
    VStack(alignment: .leading, spacing: DS.Space.sm) {
        DSText("Kind of Blue", style: .display)
        DSText("Albums", style: .title)
        DSText("Blue in Green", style: .headline)
        DSText("Miles Davis", style: .body)
        DSText("1959 · Columbia", style: .caption, color: DS.Color.textSecondary)
        DSText("Recently Added", style: .label, color: DS.Color.textTertiary)
        DSText("1:47 / 5:37 · 24/192", style: .numeric, color: DS.Color.textTertiary)
    }
    .padding(DS.Space.xl)
    .background(DS.Color.bgBase)
    .preferredColorScheme(.dark)
}

#Preview("DSText — light") {
    VStack(alignment: .leading, spacing: DS.Space.sm) {
        DSText("Kind of Blue", style: .display)
        DSText("Blue in Green", style: .headline)
        DSText("1959 · Columbia", style: .caption, color: DS.Color.textSecondary)
        DSText("1:47 / 5:37 · 24/192", style: .numeric, color: DS.Color.textTertiary)
    }
    .padding(DS.Space.xl)
    .background(DS.Color.bgBase)
    .preferredColorScheme(.light)
}
