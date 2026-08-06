import SwiftUI

/// App entry point. Thin wrapper — all logic lives in Packages/ (SPEC §3.1).
@main
struct EscapementApp: App {
    var body: some Scene {
        Window("Escapement", id: "main") {
            EmptyContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

/// Phase 0 placeholder; replaced by the three-column layout in Phase 5.
struct EmptyContentView: View {
    var body: some View {
        Color.clear
    }
}
