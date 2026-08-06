import DesignSystem
import SwiftUI

/// App entry point. Thin wrapper — all logic lives in Packages/ (SPEC §3.1).
@main
struct EscapementApp: App {
    @State private var env = Self.makeEnvironment()

    private static func makeEnvironment() -> AppEnvironment {
        do {
            return try AppEnvironment()
        } catch {
            // Без БД приложение бессмысленно — падаем с внятной причиной.
            fatalError("cannot open library database: \(error)")
        }
    }

    var body: some Scene {
        Window("Escapement", id: "main") {
            MainWindow()
                .environment(env)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Play/Pause") { env.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Next Track") { env.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Previous Track") { env.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Button("Rescan Sources") { env.rescanAll() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Search") { env.searchFocusTrigger += 1 }
                    .keyboardShortcut("f", modifiers: [.command])
                Button("New Playlist") { env.createPlaylist() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsScene()
                .environment(env)
        }

        #if DEBUG
        Window("Design Gallery", id: "design-gallery") {
            DesignSystemGallery()
        }
        // ⌘⌥D from TASKS is taken by the system Dock toggle; ⌘⇧D is free.
        .keyboardShortcut("d", modifiers: [.command, .shift])
        #endif
    }
}
