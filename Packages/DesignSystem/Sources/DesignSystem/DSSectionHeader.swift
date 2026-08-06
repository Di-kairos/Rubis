import SwiftUI

/// Sidebar section / column header: uppercase label in tertiary color (DESIGN.md §5.5).
public struct DSSectionHeader: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        DSText(title, style: .label, color: DS.Color.textTertiary)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("DSSectionHeader — dark") {
    VStack(alignment: .leading, spacing: 0) {
        DSSectionHeader("Library")
        DSSectionHeader("Playlists")
    }
    .frame(width: DS.Metrics.sidebarWidth)
    .background(DS.Color.bgRaised)
    .preferredColorScheme(.dark)
}

#Preview("DSSectionHeader — light") {
    DSSectionHeader("Library")
        .frame(width: DS.Metrics.sidebarWidth)
        .background(DS.Color.bgRaised)
        .preferredColorScheme(.light)
}
