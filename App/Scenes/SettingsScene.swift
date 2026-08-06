import AppKit
import DesignSystem
import EscapementCore
import MusicLibrary
import PlaybackEngine
import SwiftUI

/// Settings (SPEC §8): Library / Audio / Server / Keys.
struct SettingsScene: View {
    var body: some View {
        TabView {
            LibrarySettings()
                .tabItem { Label("Library", systemImage: "folder") }
            AudioSettings()
                .tabItem { Label("Audio", systemImage: "hifispeaker") }
            DSText("Server — phase 6", style: .body, color: DS.Color.textTertiary)
                .frame(width: 480, height: 200)
                .tabItem { Label("Server", systemImage: "server.rack") }
            DSText("Keys — phase 7", style: .body, color: DS.Color.textTertiary)
                .frame(width: 480, height: 200)
                .tabItem { Label("Keys", systemImage: "keyboard") }
        }
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
