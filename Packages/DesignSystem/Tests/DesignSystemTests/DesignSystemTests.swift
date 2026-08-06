import DesignSystem
import Testing

struct DesignSystemTests {
    /// Placeholder until Phase 1 brings tokens and the WCAG contrast test.
    @Test func namespaceExists() {
        #expect(String(describing: DS.self) == "DS")
    }
}
