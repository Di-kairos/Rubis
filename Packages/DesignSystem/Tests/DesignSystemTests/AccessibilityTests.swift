import SwiftUI
import Testing

@testable import DesignSystem

struct ContrastAdaptationTests {
    @Test func increasedContrastLiftsDimTextOneStep() {
        #expect(DS.Contrast.text(DS.Color.textTertiary, increased: true) == DS.Color.textSecondary)
        #expect(DS.Contrast.text(DS.Color.textSecondary, increased: true) == DS.Color.textPrimary)
    }

    @Test func normalContrastLeavesColorsAlone() {
        #expect(DS.Contrast.text(DS.Color.textTertiary, increased: false) == DS.Color.textTertiary)
        #expect(DS.Contrast.text(DS.Color.accent, increased: false) == DS.Color.accent)
    }

    @Test func accentAndPrimaryAreNeverRemapped() {
        // Акцент — смысловой цвет, поднимать его некуда и незачем.
        #expect(DS.Contrast.text(DS.Color.accent, increased: true) == DS.Color.accent)
        #expect(DS.Contrast.text(DS.Color.textPrimary, increased: true) == DS.Color.textPrimary)
    }

    @Test func hairlineBecomesStrongStroke() {
        #expect(DS.Contrast.stroke(increased: true) == DS.Color.strokeStrong)
        #expect(DS.Contrast.stroke(increased: false) == DS.Color.strokeHairline)
    }
}
