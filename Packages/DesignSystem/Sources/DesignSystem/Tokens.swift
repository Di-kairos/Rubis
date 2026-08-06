// AppKit is required here: SwiftUI.Color has no appearance-adaptive initializer,
// NSColor(name:dynamicProvider:) is the only way to get automatic dark/light
// resolution without observing the appearance manually (DESIGN.md §9).
import AppKit
import SwiftUI

/// Wraps a ColorPair into a SwiftUI Color that resolves per current appearance.
private func adaptive(_ pair: ColorPair) -> SwiftUI.Color {
    SwiftUI.Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? pair.dark.nsColor : pair.light.nsColor
        })
}

extension DS {
    /// Semantic colors (DESIGN.md §2). The only color source outside album covers.
    public enum Color {
        public static let bgBase = adaptive(Palette.bgBase)
        public static let bgRaised = adaptive(Palette.bgRaised)
        public static let bgOverlay = adaptive(Palette.bgOverlay)
        public static let bgHover = adaptive(Palette.bgHover)
        public static let bgSelected = adaptive(Palette.bgSelected)
        public static let strokeHairline = adaptive(Palette.strokeHairline)
        public static let strokeStrong = adaptive(Palette.strokeStrong)
        public static let textPrimary = adaptive(Palette.textPrimary)
        public static let textSecondary = adaptive(Palette.textSecondary)
        public static let textTertiary = adaptive(Palette.textTertiary)
        public static let textDisabled = adaptive(Palette.textDisabled)
        public static let accent = adaptive(Palette.accent)
        public static let accentMuted = adaptive(Palette.accentMuted)
        public static let warning = adaptive(Palette.warning)
        public static let danger = adaptive(Palette.danger)
    }

    /// Typography (DESIGN.md §3). System fonts only.
    public enum Font {
        public static let display = SwiftUI.Font.system(size: 28, weight: .bold)
        /// Артист под названием альбома — акцентным цветом (DESIGN §3).
        public static let displayArtist = SwiftUI.Font.system(size: 22, weight: .regular)
        public static let title = SwiftUI.Font.system(size: 20, weight: .medium)
        public static let headline = SwiftUI.Font.system(size: 14, weight: .semibold)
        public static let body = SwiftUI.Font.system(size: 13, weight: .regular)
        public static let caption = SwiftUI.Font.system(size: 11, weight: .regular)
        public static let label = SwiftUI.Font.system(size: 10, weight: .medium)
        /// Tabular numerals for timings, rates and bit depth — never proportional.
        public static let numeric = SwiftUI.Font.system(size: 12, design: .monospaced)
            .monospacedDigit()

        public enum Tracking {
            public static let display: CGFloat = -0.4
            public static let caption: CGFloat = 0.2
            public static let label: CGFloat = 0.8
        }

        public enum LineSpacing {
            /// Multiline body text multiplier (DESIGN.md §3).
            public static let multiline: CGFloat = 1.35
        }
    }

    /// 4 pt base grid (DESIGN.md §4).
    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        /// Cards and input fields.
        public static let card: CGFloat = 6
        /// Small elements (covers in transport, badges).
        public static let small: CGFloat = 4
        /// List rows are never rounded.
        public static let row: CGFloat = 0
    }

    /// Fixed element metrics (DESIGN.md §4).
    public enum Metrics {
        public static let trackRowCompact: CGFloat = 32
        public static let trackRowWithCover: CGFloat = 44
        public static let sidebarRow: CGFloat = 28
        public static let transportBar: CGFloat = 72
        public static let sidebarWidth: CGFloat = 220
        public static let sidebarWidthMin: CGFloat = 180
        public static let sidebarWidthMax: CGFloat = 320
        public static let transportCover: CGFloat = 52
        public static let albumGridCover: CGFloat = 176
        public static let albumGridGap: CGFloat = 16
        public static let iconList: CGFloat = 16
        public static let iconTransport: CGFloat = 20
        public static let iconPlay: CGFloat = 28
        public static let windowMinWidth: CGFloat = 900
        public static let windowMinHeight: CGFloat = 600
        public static let progressBarHeight: CGFloat = 3
        public static let progressBarHeightHover: CGFloat = 5
        public static let miniPlayerSize = CGSize(width: 240, height: 80)
    }

    /// Motion (DESIGN.md §6). No springs anywhere; check Reduce Motion at call sites.
    public enum Motion {
        public static let hover = Animation.easeOut(duration: 0.12)
        public static let popover = Animation.easeOut(duration: 0.18)
        public static let trackChange = Animation.easeInOut(duration: 0.24)
        /// Progress bar animates linearly, updated at 10 Hz.
        public static let progress = Animation.linear(duration: 0.1)
    }

    /// The single allowed shadow (DESIGN.md §2.3): popovers and overlays only.
    public enum Shadow {
        public static let overlayColor = adaptive(Palette.overlayShadow)
        public static let overlayRadius: CGFloat = 16
        public static let overlayY: CGFloat = 8
    }
}
