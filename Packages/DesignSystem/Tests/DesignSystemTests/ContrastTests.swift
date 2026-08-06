import Foundation
import Testing

@testable import DesignSystem

/// WCAG contrast requirements from DESIGN.md §2.3, computed — not eyeballed.
struct ContrastTests {
    /// WCAG relative luminance of an opaque sRGB color.
    private func luminance(_ c: RGBA) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private func contrastRatio(_ a: RGBA, _ b: RGBA) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test func textPrimaryOnBgBaseIsAtLeast12ToOne() {
        let dark = contrastRatio(Palette.textPrimary.dark, Palette.bgBase.dark)
        let light = contrastRatio(Palette.textPrimary.light, Palette.bgBase.light)
        #expect(dark >= 12.0, "dark mode: \(dark)")
        #expect(light >= 12.0, "light mode: \(light)")
    }

    @Test func textSecondaryOnBgBaseIsAtLeast4Point5ToOne() {
        let dark = contrastRatio(Palette.textSecondary.dark, Palette.bgBase.dark)
        let light = contrastRatio(Palette.textSecondary.light, Palette.bgBase.light)
        #expect(dark >= 4.5, "dark mode: \(dark)")
        #expect(light >= 4.5, "light mode: \(light)")
    }

    /// Alpha-composited tokens must stay effectively invisible as text backers —
    /// hover/selected overlays may not push text below thresholds. Composite
    /// bg.selected over bg.base and re-check primary text on top of it.
    @Test func textPrimaryOnSelectedRowStillReadable() {
        func composite(_ top: RGBA, over base: RGBA) -> RGBA {
            RGBA(
                r: top.r * top.a + base.r * (1 - top.a),
                g: top.g * top.a + base.g * (1 - top.a),
                b: top.b * top.a + base.b * (1 - top.a))
        }
        let darkSelected = composite(Palette.bgSelected.dark, over: Palette.bgBase.dark)
        let lightSelected = composite(Palette.bgSelected.light, over: Palette.bgBase.light)
        #expect(contrastRatio(Palette.textPrimary.dark, darkSelected) >= 12.0)
        #expect(contrastRatio(Palette.textPrimary.light, lightSelected) >= 12.0)
    }
}
