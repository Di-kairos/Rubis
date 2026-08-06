import DesignSystem
import SwiftUI

/// App entry point. Thin wrapper — all logic lives in Packages/ (SPEC §3.1).
@main
struct EscapementApp: App {
    var body: some Scene {
        Window("Escapement", id: "main") {
            EmptyContentView()
                .frame(
                    minWidth: DS.Metrics.windowMinWidth,
                    minHeight: DS.Metrics.windowMinHeight)
        }
        .windowStyle(.hiddenTitleBar)

        #if DEBUG
        Window("Design Gallery", id: "design-gallery") {
            DesignSystemGallery()
        }
        .keyboardShortcut("d", modifiers: [.command, .option])
        #endif
    }
}

/// Phase 0 placeholder; replaced by the three-column layout in Phase 5.
struct EmptyContentView: View {
    var body: some View {
        Color.clear
    }
}
