import DesignSystem
import Sparkle
import SwiftUI

/// Обновления (D-005): проверка при запуске и, по желанию, установка без
/// вопросов. Источник правды — сам Sparkle: галки читают и пишут его
/// свойства, а не собственную копию в UserDefaults.
struct UpdateSettings: View {
    let updater: SPUUpdater

    @State private var automaticChecks = true
    @State private var automaticInstall = false
    @State private var lastCheck: Date?

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates at launch and in the background", isOn: $automaticChecks)
                .onChange(of: automaticChecks) {
                    updater.automaticallyChecksForUpdates = automaticChecks
                }
            Toggle("Download and install them automatically", isOn: $automaticInstall)
                .disabled(!automaticChecks)
                .onChange(of: automaticInstall) {
                    updater.automaticallyDownloadsUpdates = automaticInstall
                }
                .help("The update is applied the next time you quit Rubis Music")
            HStack {
                DSText(lastCheckText, style: .caption, color: DS.Color.textSecondary)
                Spacer()
                Button("Check now") { updater.checkForUpdates() }
            }
        }
        .task {
            automaticChecks = updater.automaticallyChecksForUpdates
            automaticInstall = updater.automaticallyDownloadsUpdates
            lastCheck = updater.lastUpdateCheckDate
        }
    }

    private var lastCheckText: String {
        guard let lastCheck else { return "Never checked yet" }
        return "Last checked \(lastCheck.formatted(date: .abbreviated, time: .shortened))"
    }
}
