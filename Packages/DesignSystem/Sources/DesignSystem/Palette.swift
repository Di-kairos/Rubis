import AppKit

/// Raw sRGB color storage shared by the runtime tokens and the WCAG contrast test.
/// Values are verbatim from DESIGN.md §2 — edit there first, then here.
struct RGBA: Equatable, Sendable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(_ hex: UInt32, alpha: Double = 1.0) {
        r = Double((hex >> 16) & 0xFF) / 255.0
        g = Double((hex >> 8) & 0xFF) / 255.0
        b = Double(hex & 0xFF) / 255.0
        a = alpha
    }

    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

/// One token, both appearance modes (DESIGN.md §2.1 Obsidian / §2.2 Porcelain).
struct ColorPair: Sendable {
    let dark: RGBA
    let light: RGBA
}

enum Palette {
    static let bgBase = ColorPair(dark: RGBA(0x0B0B0C), light: RGBA(0xFAF8F5))
    static let bgRaised = ColorPair(dark: RGBA(0x141416), light: RGBA(0xFFFFFF))
    static let bgOverlay = ColorPair(dark: RGBA(0x1C1C1F), light: RGBA(0xFFFFFF))
    static let bgHover = ColorPair(
        dark: RGBA(0xFFFFFF, alpha: 0.04), light: RGBA(0x000000, alpha: 0.035))
    static let bgSelected = ColorPair(
        dark: RGBA(0xFFFFFF, alpha: 0.07), light: RGBA(0x000000, alpha: 0.06))
    static let strokeHairline = ColorPair(
        dark: RGBA(0xFFFFFF, alpha: 0.07), light: RGBA(0x000000, alpha: 0.08))
    static let strokeStrong = ColorPair(
        dark: RGBA(0xFFFFFF, alpha: 0.14), light: RGBA(0x000000, alpha: 0.16))
    static let textPrimary = ColorPair(dark: RGBA(0xF2F0EC), light: RGBA(0x1A1917))
    static let textSecondary = ColorPair(dark: RGBA(0x96948E), light: RGBA(0x6B6862))
    static let textTertiary = ColorPair(dark: RGBA(0x5A5854), light: RGBA(0x9A968E))
    static let textDisabled = ColorPair(dark: RGBA(0x3A3937), light: RGBA(0xC4C0B8))
    static let accent = ColorPair(dark: RGBA(0xC2A15A), light: RGBA(0x8A6C2E))
    static let accentMuted = ColorPair(dark: RGBA(0x7A6739), light: RGBA(0xB5A47E))
    static let warning = ColorPair(dark: RGBA(0xC87F4A), light: RGBA(0xA25E2B))
    static let danger = ColorPair(dark: RGBA(0xB4534A), light: RGBA(0x96382F))
    static let overlayShadow = ColorPair(
        dark: RGBA(0x000000, alpha: 0.4), light: RGBA(0x000000, alpha: 0.4))
}
