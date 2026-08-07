import AppKit
import DesignSystem
import EscapementCore
import MusicLibrary
import PlaybackEngine
import SwiftUI

/// Settings (SPEC §8): Library / Audio / Server / Keys.
/// ASSUMPTION: вкладка General добавлена сверх списка §8 — присутствие в системе
/// (меню-бар, mini player поверх окон) не относится ни к одной из четырёх.
struct SettingsScene: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            LibrarySettings()
                .tabItem { Label("Library", systemImage: "folder") }
            AudioSettings()
                .tabItem { Label("Audio", systemImage: "hifispeaker") }
            DSText("Server — phase 6", style: .body, color: DS.Color.textTertiary)
                .frame(width: 480, height: 200)
                .tabItem { Label("Server", systemImage: "server.rack") }
            KeysSettings()
                .tabItem { Label("Keys", systemImage: "keyboard") }
        }
        .frame(width: 520)
    }
}

/// Keys (SPEC §8): глобальные медиа-клавиши и справка по горячим клавишам §7.6.
/// Переопределение сочетаний — не в этой фазе, список только показывается.
struct KeysSettings: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage(SettingsKey.globalMediaKeys) private var globalMediaKeys = false
    @State private var trusted = GlobalMediaKeys.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Global media keys", isOn: $globalMediaKeys)
                    .help("Play, next and previous work while another app is in front")
                if globalMediaKeys && !trusted {
                    // Разрешение выдаётся в System Settings и подхватывается
                    // не мгновенно — поэтому статус с кнопкой, а не молчание.
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(DS.Color.warning)
                            .accessibilityHidden(true)
                        DSText(
                            "Needs Accessibility access", style: .caption,
                            color: DS.Color.textSecondary)
                        Button("Grant…") {
                            GlobalMediaKeys.requestTrust()
                            openAccessibilitySettings()
                        }
                        Button("Recheck") { refreshTrust() }
                    }
                }
            }
            Section("Shortcuts") {
                ForEach(Self.shortcuts, id: \.0) { name, keys in
                    HStack {
                        DSText(name, style: .body)
                        Spacer()
                        DSText(keys, style: .numeric, color: DS.Color.textSecondary)
                    }
                }
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 520)
        .onChange(of: globalMediaKeys) { apply() }
        .task { apply() }
    }

    /// Список из SPEC §7.6 — справка, пока переопределения нет.
    private static let shortcuts: [(String, String)] = [
        ("Play / Pause", "Space"),
        ("Next / previous track", "⌘→  ⌘←"),
        ("Seek ±5 s", "→  ←"),
        ("Search", "⌘F"),
        ("Mini player", "⌘⇧M"),
        ("Show current track", "⌘L"),
        ("New playlist", "⌘⇧N"),
        ("Rescan sources", "⌘R"),
        ("Settings", "⌘,"),
    ]

    private func apply() {
        refreshTrust()
        // Включение без разрешения не притворяется успешным: тумблер
        // возвращается назад, а рядом остаётся объяснение.
        if globalMediaKeys, env.globalMediaKeys?.setEnabled(true) != true, !trusted {
            return
        }
        if !globalMediaKeys { _ = env.globalMediaKeys?.setEnabled(false) }
    }

    private func refreshTrust() {
        trusted = GlobalMediaKeys.isTrusted
    }

    private func openAccessibilitySettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Присутствие приложения в системе (SPEC §7.5): обе опции выключены по
/// умолчанию — ничего не лезет в меню-бар и поверх чужих окон без спроса.
struct GeneralSettings: View {
    @AppStorage(SettingsKey.menuBarIcon) private var menuBarIcon = false
    @AppStorage(SettingsKey.miniPlayerOnTop) private var miniPlayerOnTop = false

    var body: some View {
        Form {
            Toggle("Show icon in the menu bar", isOn: $menuBarIcon)
                .help("Current track and transport without bringing the window up")
            Toggle("Keep mini player above other windows", isOn: $miniPlayerOnTop)
        }
        .padding(DS.Space.xl)
        .frame(width: 520)
    }
}

struct LibrarySettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var sources: [Source] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            DSText("Sources", style: .title)
            ForEach(sources) { source in
                HStack {
                    Image(systemName: source.kind == .local ? "folder" : "server.rack")
                        .foregroundStyle(DS.Color.textSecondary)
                        .accessibilityHidden(true)
                    DSText(source.displayName, style: .body)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        removeSource(source)
                    }
                    .font(DS.Font.caption)
                }
            }
            HStack {
                Button("Add Folder…") { addFolder() }
                Spacer()
                Button("Rescan All") { env.rescanAll() }
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 520, alignment: .leading)
        .task { reload() }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            env.addFolderSource(url: url)
            // источник появится в списке после первого скана
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { reload() }
        }
    }

    private func removeSource(_ source: Source) {
        // Один из двух разрешённых модальных алертов (SPEC §9)
        let alert = NSAlert()
        alert.messageText = "Remove source “\(source.displayName)”?"
        alert.informativeText = "Tracks from this source will be removed from the library."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            try? env.sourceRepo.delete(id: source.id)
            reload()
        }
    }

    private func reload() {
        sources = (try? env.sourceRepo.all()) ?? []
    }
}

struct AudioSettings: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage("exclusiveAccess") private var exclusiveAccess = true
    @AppStorage("rateChangeDelayMs") private var rateChangeDelayMs = 300
    @AppStorage("rateFallback") private var rateFallback = "nearestFamilyMultiple"
    @AppStorage("dsdMode") private var dsdMode = "dopIfAvailable"

    var body: some View {
        Form {
            Toggle("Exclusive access (hog mode)", isOn: $exclusiveAccess)
            Stepper(
                "Sample-rate change delay: \(rateChangeDelayMs) ms",
                value: $rateChangeDelayMs, in: 0...1000, step: 100)
            Picker("If exact rate unavailable", selection: $rateFallback) {
                Text("Nearest family multiple").tag("nearestFamilyMultiple")
                Text("Allow cross-family resample").tag("allowCrossFamily")
                Text("Refuse to play").tag("refuse")
            }
            Picker("DSD mode", selection: $dsdMode) {
                Text("DoP if available").tag("dopIfAvailable")
                Text("Always convert to PCM").tag("alwaysConvertToPCM")
            }
            Picker("ReplayGain", selection: .constant("off")) {
                Text("Off").tag("off")
            }
            .disabled(true)
            .help("ReplayGain is stored but never applied in v1 — bit-perfect first (SPEC §5.3)")
        }
        .padding(DS.Space.xl)
        .frame(width: 520)
        .onChange(of: exclusiveAccess) { pushConfig() }
        .onChange(of: rateChangeDelayMs) { pushConfig() }
        .onChange(of: rateFallback) { pushConfig() }
        .onChange(of: dsdMode) { pushConfig() }
        .task { pushConfig() }
    }

    private func pushConfig() {
        let config = AudioConfiguration(
            exclusiveAccess: exclusiveAccess,
            sampleRateChangeDelay: .milliseconds(rateChangeDelayMs),
            rateFallback: .init(rawValue: rateFallback) ?? .nearestFamilyMultiple,
            dsdMode: .init(rawValue: dsdMode) ?? .dopIfAvailable)
        Task { await env.player.update(configuration: config) }
    }
}
