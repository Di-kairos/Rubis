import AppKit
import DesignSystem
import EscapementCore
import MusicLibrary
import PlaybackEngine
import Sparkle
import SwiftUI

/// Settings (SPEC §8): Library / Audio / Server / Keys.
/// ASSUMPTION: вкладка General добавлена сверх списка §8 — присутствие в системе
/// (меню-бар, mini player поверх окон) не относится ни к одной из четырёх.
struct SettingsScene: View {
    /// Sparkle приходит из приложения: обновления настраиваются здесь, а
    /// живёт контроллер там же, где создан (без синглтонов).
    let updater: SPUUpdater

    var body: some View {
        TabView {
            GeneralSettings(updater: updater)
                .tabItem { Label("General", systemImage: "gearshape") }
            LibrarySettings()
                .tabItem { Label("Library", systemImage: "folder") }
            AudioSettings()
                .tabItem { Label("Audio", systemImage: "hifispeaker") }
            ServerSettings()
                .tabItem { Label("Server", systemImage: "server.rack") }
            NetworkSettings()
                .tabItem { Label("Network", systemImage: "antenna.radiowaves.left.and.right") }
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
                        Button("Recheck") { apply() }
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

    /// Само включение висит на приложении (оно же поднимает монитор при
    /// запуске) — здесь только повторная попытка после выдачи разрешения.
    private func apply() {
        trusted = GlobalMediaKeys.isTrusted
        _ = env.globalMediaKeys?.setEnabled(globalMediaKeys)
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
    let updater: SPUUpdater
    @Environment(AppEnvironment.self) private var env
    @AppStorage(SettingsKey.menuBarIcon) private var menuBarIcon = false
    @AppStorage(SettingsKey.miniPlayerOnTop) private var miniPlayerOnTop = false
    /// Оформление плеера отдельно от macOS: Obsidian можно держать при светлой
    /// системе и наоборот.
    @AppStorage(SettingsKey.appearance) private var appearance = AppAppearance.system.rawValue
    /// D-008: аннотации альбомов — opt-in, сеть только по явному включению.
    @AppStorage("albumNotes") private var albumNotes = false
    /// Писатель fallback-заметок (D-008): Claude или DeepSeek, ключ каждого
    /// хранится в Keychain под своим account.
    @AppStorage("notesProvider") private var notesProvider = NotesProvider.claude.rawValue
    @State private var apiKey =
        KeychainStore.load(account: NotesProvider.claude.keychainAccount) ?? ""

    private var provider: NotesProvider {
        NotesProvider(rawValue: notesProvider) ?? .claude
    }

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .help("Follows macOS unless you pin the player to light or dark")
            Toggle("Show icon in the menu bar", isOn: $menuBarIcon)
                .help("Current track and transport without bringing the window up")
            Toggle("Keep mini player above other windows", isOn: $miniPlayerOnTop)
            Section("Album notes") {
                Toggle("Show liner notes while a track is playing", isOn: $albumNotes)
                    .help(
                        "Written once per album by the selected writer; Wikipedia "
                            + "steps in when there is no key or the album is unknown. "
                            + "Cached forever.")
                Picker("Notes writer", selection: $notesProvider) {
                    ForEach(NotesProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                SecureField("\(provider.displayName) API key", text: $apiKey)
                    .onChange(of: apiKey) {
                        KeychainStore.save(apiKey, account: provider.keychainAccount)
                        // Ключ в акторе кешируется на запуск — сбросить,
                        // иначе новый ключ заработает только после перезапуска.
                        Task { await env.albumInfo.forgetKeys() }
                    }
                    .help("Stored in the Keychain, sent only to the selected provider")
            }
            UpdateSettings(updater: updater)
        }
        .padding(DS.Space.xl)
        .frame(width: 520)
        // Применяем здесь, а не в главном окне: оно может быть закрыто
        // (режим меню-бара), а Settings в этот момент открыт.
        .onChange(of: appearance) { AppAppearance.apply(appearance) }
        // Смена писателя — поле показывает ключ выбранного провайдера.
        .onChange(of: notesProvider) {
            apiKey = KeychainStore.load(account: provider.keychainAccount) ?? ""
        }
    }
}

struct LibrarySettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var sources: [Source] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            DSText("Sources", style: .title)
            // Скроллится: десятки источников не должны распирать окно Settings
            // (та же болезнь, что была у сайдбара до 0.3.1).
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    ForEach(sources) { source in
                        HStack {
                            Image(
                                systemName: source.kind == .local ? "folder" : "server.rack"
                            )
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
                }
            }
            .frame(maxHeight: 240)
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
            // У сервера вместе с записью уходит пароль — иначе он остался бы
            // в связке сиротой (SPEC §6.1).
            if source.kind == .subsonic, let url = source.serverUrl, let user = source.username {
                SubsonicPasswordStore.delete(host: SubsonicAccount.host(of: url), username: user)
            }
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
    /// Пустая строка — следовать системному default-выходу.
    @AppStorage("preferredDeviceUID") private var preferredDeviceUID = ""
    @State private var devices: [AudioDeviceController.DeviceInfo] = []
    /// Устройство, о котором показываем досье: выбранное или системное.
    @State private var dossierDeviceID: UInt32?

    /// Свой экземпляр только для перечисления — HAL-запросы дёшевы,
    /// трогать актор плеера ради списка не нужно.
    private let enumerator = AudioDeviceController()

    private var isPlaying: Bool {
        if case .playing = env.playbackState { return true }
        return false
    }

    var body: some View {
        Form {
            Picker("Output device", selection: $preferredDeviceUID) {
                Text("System default").tag("")
                ForEach(devices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .help(
                "Takes effect from the next track. If the device is unplugged, pick System default."
            )
            Toggle("Exclusive access (hog mode)", isOn: $exclusiveAccess)
            Stepper(
                "Sample-rate change delay: \(rateChangeDelayMs) ms",
                value: $rateChangeDelayMs, in: 0...1000, step: 100)
            Picker("If exact rate unavailable", selection: $rateFallback) {
                Text("Nearest family multiple").tag("nearestFamilyMultiple")
                Text("Allow cross-family resample").tag("allowCrossFamily")
                Text("Bit-perfect or silence — refuse to play").tag("refuse")
            }
            .help(
                "The last option never resamples: a track the device cannot play exactly "
                    + "stays silent and says so, instead of playing altered.")
            Picker("DSD mode", selection: $dsdMode) {
                Text("DoP if available").tag("dopIfAvailable")
                Text("Always convert to PCM").tag("alwaysConvertToPCM")
            }
            Picker("ReplayGain", selection: .constant("off")) {
                Text("Off").tag("off")
            }
            .disabled(true)
            .help("ReplayGain is stored but never applied in v1 — bit-perfect first (SPEC §5.3)")
            Section("What this device can do") {
                DeviceDossierCard(deviceID: dossierDeviceID, playing: isPlaying)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 520)
        .onChange(of: exclusiveAccess) { pushConfig() }
        .onChange(of: rateChangeDelayMs) { pushConfig() }
        .onChange(of: rateFallback) { pushConfig() }
        .onChange(of: dsdMode) { pushConfig() }
        .onChange(of: preferredDeviceUID) {
            pushConfig()
            Task { await resolveDossierDevice() }
        }
        .task {
            devices = (try? await enumerator.outputDevices()) ?? []
            await resolveDossierDevice()
            pushConfig()
        }
    }

    /// Пустой UID — досье на системный выход: именно в него и будет играть.
    private func resolveDossierDevice() async {
        if preferredDeviceUID.isEmpty {
            dossierDeviceID = try? await enumerator.defaultOutputDevice()?.id
        } else {
            dossierDeviceID = devices.first { $0.uid == preferredDeviceUID }?.id
        }
    }

    /// @AppStorage уже записал значение в UserDefaults — маппинг ключей
    /// в конфиг один, в AppEnvironment.storedAudioConfiguration().
    private func pushConfig() {
        env.applyStoredAudioConfiguration()
    }
}
