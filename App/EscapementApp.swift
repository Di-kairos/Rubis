import DesignSystem
import SwiftUI

/// App entry point. Thin wrapper — all logic lives in Packages/ (SPEC §3.1).
@main
struct EscapementApp: App {
    @State private var env = Self.makeEnvironment()
    @State private var media: MediaIntegration?

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
                .task {
                    media = MediaIntegration(env: env)
                    media?.update()
                }
                .onChange(of: env.playbackState) { media?.update() }
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
                Button("Seek Forward") { env.seek(by: 5) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Seek Backward") { env.seek(by: -5) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Search") { env.searchFocusTrigger += 1 }
                    .keyboardShortcut("f", modifiers: [.command])
                Button("Show Current Track") { env.revealCurrentTrack() }
                    .keyboardShortcut("l", modifiers: [.command])
                Button("New Playlist") { env.createPlaylist() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsScene()
                .environment(env)
        }

        // SPEC §7.6 хочет ⌘⌥M, но система держит его; берём ⌘⇧M (kickoff S02).
        Window("Mini Player", id: "mini-player") {
            MiniPlayer()
                .environment(env)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .keyboardShortcut("m", modifiers: [.command, .shift])

        #if DEBUG
        Window("Design Gallery", id: "design-gallery") {
            DesignSystemGallery()
        }
        // ⌘⌥D from TASKS is taken by the system Dock toggle; ⌘⇧D is free.
        .keyboardShortcut("d", modifiers: [.command, .shift])
        #endif
    }
}
