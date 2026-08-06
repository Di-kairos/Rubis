import SwiftUI

/// Neutral icon button (SF Symbol). Transport and list actions.
/// Accessibility label is mandatory (DESIGN.md §8).
public struct DSIconButton: View {
    private let systemName: String
    private let size: CGFloat
    private let accessibilityLabel: String
    private let action: () -> Void

    @State private var hovering = false

    public init(
        _ systemName: String,
        size: CGFloat = DS.Metrics.iconList,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(hovering ? DS.Color.textPrimary : DS.Color.textSecondary)
                .frame(width: size + DS.Space.md, height: size + DS.Space.md)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DS.Motion.hover, value: hovering)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("DSIconButton — dark") {
    HStack(spacing: DS.Space.lg) {
        DSIconButton(
            "backward.fill", size: DS.Metrics.iconTransport, accessibilityLabel: "Previous"
        ) {}
        DSIconButton("play.fill", size: DS.Metrics.iconPlay, accessibilityLabel: "Play") {}
        DSIconButton("forward.fill", size: DS.Metrics.iconTransport, accessibilityLabel: "Next") {}
    }
    .padding(DS.Space.xl)
    .background(DS.Color.bgRaised)
    .preferredColorScheme(.dark)
}

#Preview("DSIconButton — light") {
    HStack(spacing: DS.Space.lg) {
        DSIconButton(
            "backward.fill", size: DS.Metrics.iconTransport, accessibilityLabel: "Previous"
        ) {}
        DSIconButton("play.fill", size: DS.Metrics.iconPlay, accessibilityLabel: "Play") {}
        DSIconButton("forward.fill", size: DS.Metrics.iconTransport, accessibilityLabel: "Next") {}
    }
    .padding(DS.Space.xl)
    .background(DS.Color.bgRaised)
    .preferredColorScheme(.light)
}
