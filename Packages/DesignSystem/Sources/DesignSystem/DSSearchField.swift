import SwiftUI

/// The single app-wide search field (DESIGN.md §5.6):
/// borderless at rest on bg.raised, 1 pt accent border when focused.
public struct DSSearchField: View {
    @Binding private var text: String
    private let placeholder: String

    @FocusState private var focused: Bool

    public init(text: Binding<String>, placeholder: String = "Search") {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(DS.Color.textTertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
                .focused($focused)
        }
        .padding(.horizontal, DS.Space.sm)
        .frame(height: 28)
        .background(DS.Color.bgRaised)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.small)
                .strokeBorder(focused ? DS.Color.accent : .clear, lineWidth: 1)
        )
        .dsAnimation(DS.Motion.hover, value: focused)
        .accessibilityLabel("Search")
    }
}

#Preview("DSSearchField — dark") {
    VStack(spacing: DS.Space.md) {
        DSSearchField(text: .constant(""))
        DSSearchField(text: .constant("miles davis"))
    }
    .padding(DS.Space.xl)
    .frame(width: DS.Metrics.sidebarWidth + DS.Space.xxl)
    .background(DS.Color.bgBase)
    .preferredColorScheme(.dark)
}

#Preview("DSSearchField — light") {
    DSSearchField(text: .constant("miles davis"))
        .padding(DS.Space.xl)
        .frame(width: DS.Metrics.sidebarWidth + DS.Space.xxl)
        .background(DS.Color.bgBase)
        .preferredColorScheme(.light)
}
