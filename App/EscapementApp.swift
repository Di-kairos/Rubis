import DesignSystem
import EscapementCore
import Sparkle
import SwiftUI

/// App entry point. Thin wrapper — all logic lives in Packages/ (SPEC §3.1).
@main
struct EscapementApp: App {
    /// Бюджет §12: холодный старт < 800 мс. Точка отсчёта — exec процесса
    /// (kinfo_proc), т.е. метрика включает dyld и весь путь до первого кадра.
    static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        return Date(
            timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    @State private var env = Self.makeEnvironment()
    @State private var media: MediaIntegration?
    /// Sparkle (D-005): проверка и установка обновлений из rubis-releases.
    private let updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private static func makeEnvironment() -> AppEnvironment {
        do {
            return try AppEnvironment()
        } catch {
            // Без БД приложение бессмысленно — падаем с внятной причиной.
            fatalError("cannot open library database: \(error)")
        }
    }

    var body: some Scene {
        Window("Rubis Music", id: "main") {
            MainWindow()
                .environment(env)
                .task {
                    if let start = Self.processStartDate() {
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        Log.ui.info("launch to interactive window: \(ms, privacy: .public) ms")
                    }
                    media = MediaIntegration(env: env)
                    media?.update()
                }
                .onChange(of: env.playbackState) { media?.update() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.updater.checkForUpdates() }
            }
            CommandGroup(after: .toolbar) {
                // Пункты без модификаторов гасим на время набора текста —
                // иначе меню съедает пробел и стрелки до текстового поля.
                Button("Play/Pause") { env.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(env.isEditingText)
                Button("Next Track") { env.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Previous Track") { env.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Button("Rescan Sources") { env.rescanAll() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Seek Forward") { env.seek(by: 5) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(env.isEditingText)
                Button("Seek Backward") { env.seek(by: -5) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(env.isEditingText)
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
