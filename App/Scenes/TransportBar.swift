import AppKit
import DesignSystem
import EscapementCore
import MusicLibrary
import PlaybackEngine
import SwiftUI

/// Transport panel (DESIGN §5.1): cover, titles, transport, progress,
/// timings and the quality badge with its popover (SPEC §7.3).
struct TransportBar: View {
    @Environment(AppEnvironment.self) private var env
    @State private var progress: Double = 0
    @State private var timeText = "0:00"
    @State private var totalText = "0:00"
    @State private var showStatusPopover = false
    /// «Copied» на пару секунд вместо алерта.
    @State private var copied = false
    /// Транспорт устройства для отчёта — HAL спрашиваем при открытии поповера.
    @State private var deviceTransport = "—"

    /// Свой экземпляр для справочных чтений: актор плеера ради транспорта
    /// устройства трогать незачем.
    private let hal = AudioDeviceController()

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            DSCoverImage(image: coverImage, size: DS.Metrics.transportCover)

            VStack(alignment: .leading, spacing: 2) {
                DSText(titleLine, style: .headline)
                DSText(subtitleLine, style: .caption, color: DS.Color.textSecondary)
            }
            .frame(width: 200, alignment: .leading)

            HStack(spacing: DS.Space.lg) {
                DSIconButton(
                    "backward.fill", size: DS.Metrics.iconTransport,
                    accessibilityLabel: "Previous"
                ) { env.previous() }
                DSIconButton(
                    isPlayingNow ? "pause.fill" : "play.fill", size: DS.Metrics.iconPlay,
                    accessibilityLabel: isPlayingNow ? "Pause" : "Play"
                ) { env.togglePlayPause() }
                DSIconButton(
                    "forward.fill", size: DS.Metrics.iconTransport,
                    accessibilityLabel: "Next"
                ) { env.next() }
            }

            HStack(spacing: DS.Space.sm) {
                orderButton(
                    icon: env.shuffleMode == .albums ? "shuffle.circle" : "shuffle",
                    isOn: env.shuffleMode != .off,
                    label: "Shuffle: \(env.shuffleMode.rawValue)"
                ) { env.cycleShuffleMode() }
                orderButton(
                    icon: env.repeatMode == .track ? "repeat.1" : "repeat",
                    isOn: env.repeatMode != .off,
                    label: "Repeat: \(env.repeatMode.rawValue)"
                ) { env.cycleRepeatMode() }
            }

            VStack(spacing: 2) {
                // Jewel Box II «Прибор»: шкала с рисками вместо слайдера.
                DSRulerScale(progress: progress) { fraction in
                    env.seek(to: fraction)
                }
                HStack {
                    DSText(timeText, style: .numeric, color: DS.Color.textTertiary)
                    Spacer()
                    DSText(totalText, style: .numeric, color: DS.Color.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)

            volumeControl

            badge
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Metrics.transportBar)
        .background(DS.Color.bgRaised)
        .onReceive(tick) { _ in refreshTime() }
        .task(id: env.outputStatus?.deviceName) { await refreshVolume() }
        // Обложка меняется только со сменой альбома — не считать её на тиках.
        .task(id: env.currentTrack?.albumId) { reloadCover() }
    }

    @State private var coverImage: NSImage?

    private func reloadCover() {
        guard let albumId = env.currentTrack?.albumId,
            let album = try? env.albumRepo.album(id: albumId),
            let hash = album.coverHash,
            let url = env.covers.url(hash: hash, size: 256)
        else {
            coverImage = nil
            return
        }
        coverImage = NSImage(contentsOf: url)
    }

    // MARK: - Hardware volume (SPEC §4.4 — только громкость устройства)

    @State private var volume: Float?

    @ViewBuilder
    private var volumeControl: some View {
        if let volume {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.textTertiary)
                    .accessibilityHidden(true)
                Slider(
                    value: Binding(
                        get: { volume },
                        set: { value in
                            self.volume = value
                            Task { await env.player.setDeviceVolume(value) }
                        })
                )
                .controlSize(.mini)
                .frame(width: 72)
                .tint(DS.Color.accent)
                .accessibilityLabel("Device volume")
            }
        }
    }

    /// nil — у устройства нет аппаратной ручки (ЦАП с собственным регулятором);
    /// слайдер честно исчезает, программного гейна не существует (SPEC §4.4).
    private func refreshVolume() async {
        guard await env.player.deviceHasVolumeControl() else {
            volume = nil
            return
        }
        volume = await env.player.deviceVolume()
    }

    /// Кнопка режима очереди: включённый режим горит акцентом, состояние —
    /// в тултипе и accessibility-метке.
    private func orderButton(
        icon: String, isOn: Bool, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: DS.Metrics.iconList))
                .foregroundStyle(isOn ? DS.Color.accent : DS.Color.textTertiary)
                .frame(width: DS.Metrics.iconList + DS.Space.md)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Badge (SPEC §7.3 — единственный источник правды: OutputStatus)

    @ViewBuilder
    private var badge: some View {
        if let status = env.outputStatus {
            Button {
                showStatusPopover.toggle()
            } label: {
                DSTechBadge(segments: badgeSegments(status), status: badgeStatus(status))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showStatusPopover) {
                statusPopover(status)
            }
        }
    }

    private func badgeSegments(_ status: OutputStatus) -> [String] {
        var format = "\(Int(status.sourceSampleRate) / 1000)"
        if status.sourceSampleRate.truncatingRemainder(dividingBy: 1000) != 0 {
            format = String(format: "%.1f", status.sourceSampleRate / 1000)
        }
        let rateSegment: String
        if status.deviceSampleRate != status.sourceSampleRate {
            rateSegment = "\(format) → \(String(format: "%.1f", status.deviceSampleRate / 1000))"
        } else {
            rateSegment = "\(status.sourceBitDepth)/\(format)"
        }
        return [
            rateSegment,
            status.isExclusive ? "Exclusive" : "Shared",
            status.deviceName,
        ]
    }

    private func badgeStatus(_ status: OutputStatus) -> DSTechBadge.Status {
        if status.isBitPerfect { return .bitPerfect }
        if status.deviceSampleRate != status.sourceSampleRate { return .resampling }
        return .degraded
    }

    private func statusPopover(_ status: OutputStatus) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSText("Signal path", style: .label, color: DS.Color.textTertiary)
            row("Device", status.deviceName)
            row("Source", "\(Int(status.sourceSampleRate)) Hz / \(status.sourceBitDepth) bit")
            row("Device rate", "\(Int(status.deviceSampleRate)) Hz")
            row("Exclusive", status.isExclusive ? "yes (hog mode)" : "no")
            if let dsd = status.dsdMode {
                row("DSD", dsd == .dopIfAvailable ? "DoP" : "PCM conversion")
            }
            row("Bit-perfect", status.isBitPerfect ? "yes" : "no")
            if !status.isBitPerfect {
                DSText(
                    status.isExclusive
                        ? "Rate mismatch — resampling"
                        : "No exclusive access — mixed by CoreAudio",
                    style: .caption, color: DS.Color.warning)
            }
            // Отчёт о тракте (фишка A): то же состояние текстом, который можно
            // унести куда угодно — с отпечатком, чтобы правку было видно.
            Divider().padding(.vertical, DS.Space.xs)
            HStack(spacing: DS.Space.sm) {
                Button(copied ? "Copied" : "Copy receipt") { copyReceipt(status) }
                Button("Save…") { saveReceipt(status) }
                Spacer()
            }
            .font(DS.Font.caption)
        }
        .padding(DS.Space.lg)
        .frame(width: 280, alignment: .leading)
        .background(DS.Color.bgOverlay)
        .task(id: status.deviceName) { await loadTransport(named: status.deviceName) }
    }

    // MARK: - Signal path receipt (фишка A)

    /// ponytail: устройство ищется по имени — id в `OutputStatus` не приходит.
    /// Два одинаково названных ЦАПа дадут транспорт первого; тянуть id через
    /// весь плеер ради строчки в отчёте не стоит.
    private func loadTransport(named name: String) async {
        guard let device = (try? await hal.outputDevices())?.first(where: { $0.name == name }),
            let dossier = try? await hal.dossier(deviceID: device.id)
        else {
            deviceTransport = "—"
            return
        }
        deviceTransport = dossier.transport
    }

    private var trackArtist: String? {
        guard let id = env.currentTrack?.artistId else { return nil }
        return (try? env.artistRepo.artist(id: id))?.name
    }

    /// Отчёт из живого состояния: то, что реально настроено сейчас, а не то,
    /// что записано в настройках «на будущее».
    private func receipt(_ status: OutputStatus) -> SignalPathReceipt {
        let defaults = UserDefaults.standard
        let track = env.currentTrack
        let bundle = Bundle.main.infoDictionary
        let version = bundle?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle?["CFBundleVersion"] as? String ?? "?"
        return SignalPathReceipt(
            date: Date(),
            appVersion: "\(version) (\(build))",
            track: track.map { "\($0.title)\(trackArtist.map { " — \($0)" } ?? "")" },
            codec: track?.codec ?? "—",
            sourceRate: status.sourceSampleRate,
            sourceBits: status.sourceBitDepth,
            channels: track?.channels ?? 2,
            deviceName: status.deviceName,
            deviceTransport: deviceTransport,
            deviceRate: status.deviceSampleRate,
            exclusive: status.isExclusive,
            // Микшер снимается вместе с эксклюзивом и только с ним.
            mixingDisabled: status.isExclusive ? true : nil,
            dsd: status.dsdMode.map { $0 == .dopIfAvailable ? "DoP if available" : "PCM" },
            fallback: Self.fallbackName(defaults.string(forKey: "rateFallback")),
            bitPerfect: status.isBitPerfect)
    }

    private static func fallbackName(_ raw: String?) -> String {
        switch raw {
        case "allowCrossFamily": return "Allow cross-family resample"
        case "refuse": return "Bit-perfect or silence"
        default: return "Nearest family multiple"
        }
    }

    private func copyReceipt(_ status: OutputStatus) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(receipt(status).rendered(), forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func saveReceipt(_ status: OutputStatus) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "signal-path.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? receipt(status).rendered().write(to: url, atomically: true, encoding: .utf8)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            DSText(label, style: .caption, color: DS.Color.textSecondary)
            Spacer()
            DSText(value, style: .numeric)
        }
    }

    // MARK: -

    private var isPlayingNow: Bool {
        if case .playing = env.playbackState { return true }
        return false
    }

    private var titleLine: String {
        switch env.playbackState {
        case .idle: return "Nothing playing"
        case .loading(let t), .playing(let t), .paused(let t): return t.title
        case .failed(let t, _): return t.title
        }
    }

    private var subtitleLine: String {
        switch env.playbackState {
        // Отказ и поломка одинаково важны, но читаются словами, а не кодом:
        // «Refused: … cannot do 192 kHz» объясняет себя без документации.
        case .failed(_, let error): return error.errorDescription ?? "Playback failed"
        case .loading: return "Loading…"
        default: return ""
        }
    }

    private func refreshTime() {
        Task {
            if let time = await env.player.playbackTime(), time.total > 0 {
                progress = time.current / time.total
                timeText = AlbumDetail.format(duration: time.current)
                totalText = AlbumDetail.format(duration: time.total)
            }
        }
    }
}
