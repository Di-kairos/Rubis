#if DEBUG
import SwiftUI

/// DEBUG-only component gallery (TASKS Phase 1). Opened from the app via ⌘⌥D.
/// Shows every primitive in one place; appearance follows the pinned scheme picker.
public struct DesignSystemGallery: View {
    @State private var scheme: ColorScheme = .dark
    @State private var searchText = "miles davis"

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                Picker("Appearance", selection: $scheme) {
                    Text("Obsidian (dark)").tag(ColorScheme.dark)
                    Text("Porcelain (light)").tag(ColorScheme.light)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                section("Colors") {
                    colorSwatches
                }
                section("Typography — DSText") {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        DSText("Kind of Blue", style: .display)
                        DSText("Albums", style: .title)
                        DSText("Blue in Green", style: .headline)
                        DSText("Miles Davis", style: .body)
                        DSText("1959 · Columbia", style: .caption, color: DS.Color.textSecondary)
                        DSText("Recently Added", style: .label, color: DS.Color.textTertiary)
                        DSText(
                            "1:47 / 5:37 · 24/192", style: .numeric, color: DS.Color.textTertiary)
                    }
                }
                section("DSIconButton") {
                    HStack(spacing: DS.Space.lg) {
                        DSIconButton(
                            "backward.fill", size: DS.Metrics.iconTransport,
                            accessibilityLabel: "Previous"
                        ) {}
                        DSIconButton(
                            "play.fill", size: DS.Metrics.iconPlay, accessibilityLabel: "Play"
                        ) {}
                        DSIconButton(
                            "forward.fill", size: DS.Metrics.iconTransport,
                            accessibilityLabel: "Next"
                        ) {}
                    }
                }
                section("DSListRow") {
                    VStack(spacing: 0) {
                        row(number: "3", title: "Blue in Green", duration: "5:37", selected: false)
                        row(number: "4", title: "All Blues", duration: "11:33", selected: true)
                    }
                    .frame(width: 420)
                }
                section("DSSectionHeader") {
                    DSSectionHeader("Library")
                        .frame(width: DS.Metrics.sidebarWidth)
                        .background(DS.Color.bgRaised)
                }
                section("DSSearchField") {
                    DSSearchField(text: $searchText)
                        .frame(width: DS.Metrics.sidebarWidth)
                }
                section("DSProgressBar") {
                    DSProgressBar(progress: 0.32)
                        .frame(width: 420)
                }
                section("DSCoverImage") {
                    HStack(spacing: DS.Space.lg) {
                        DSCoverImage(size: DS.Metrics.transportCover)
                        DSCoverImage(size: DS.Metrics.albumGridCover, radius: DS.Radius.card)
                    }
                }
                section("DSTechBadge") {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        DSTechBadge(
                            segments: ["FLAC 24/192", "Exclusive", "RME ADI-2"],
                            status: .bitPerfect)
                        DSTechBadge(
                            segments: ["FLAC 24/192", "Shared", "Built-in Output"],
                            status: .degraded)
                        DSTechBadge(
                            segments: ["192 → 96", "Exclusive", "RME ADI-2"],
                            status: .resampling)
                    }
                }
            }
            .padding(DS.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.Color.bgBase)
        .preferredColorScheme(scheme)
        .frame(minWidth: galleryMinWidth, minHeight: galleryMinHeight)
    }

    /// Gallery window floor — sized to fit the widest section without clipping.
    private let galleryMinWidth: CGFloat = 760
    private let galleryMinHeight: CGFloat = 600

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            DSText(title, style: .label, color: DS.Color.textTertiary)
            content()
        }
    }

    private func row(number: String, title: String, duration: String, selected: Bool) -> some View {
        DSListRow(isSelected: selected) {
            HStack {
                DSText(number, style: .numeric, color: DS.Color.textTertiary)
                DSText(
                    title, style: .headline,
                    color: selected ? DS.Color.accent : DS.Color.textPrimary)
                Spacer()
                DSText(duration, style: .numeric, color: DS.Color.textTertiary)
            }
        }
    }

    private var colorSwatches: some View {
        let tokens: [(String, SwiftUI.Color)] = [
            ("bg.base", DS.Color.bgBase), ("bg.raised", DS.Color.bgRaised),
            ("bg.overlay", DS.Color.bgOverlay), ("text.primary", DS.Color.textPrimary),
            ("text.secondary", DS.Color.textSecondary), ("text.tertiary", DS.Color.textTertiary),
            ("accent", DS.Color.accent), ("accent.muted", DS.Color.accentMuted),
            ("warning", DS.Color.warning), ("danger", DS.Color.danger),
        ]
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(120), alignment: .leading), count: 5),
            alignment: .leading, spacing: DS.Space.md
        ) {
            ForEach(tokens, id: \.0) { name, color in
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    RoundedRectangle(cornerRadius: DS.Radius.small)
                        .fill(color)
                        .frame(width: 104, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.small)
                                .strokeBorder(DS.Color.strokeHairline, lineWidth: 1)
                        )
                    DSText(name, style: .caption, color: DS.Color.textSecondary)
                }
            }
        }
    }
}

#Preview("Gallery — dark") {
    DesignSystemGallery()
        .frame(width: 760, height: 900)
}
#endif
