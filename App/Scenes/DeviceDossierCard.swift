import DesignSystem
import PlaybackEngine
import SwiftUI

/// Досье на выбранный выход (фишка B, локальная половина): что железо
/// действительно принимает — по опросу HAL, а не по коробке. Публичной базы
/// устройств нет намеренно (SPEC §1.2).
struct DeviceDossierCard: View {
    let deviceID: UInt32?
    /// Проверка hog забирает устройство на мгновение — во время
    /// воспроизведения кнопка недоступна.
    let playing: Bool

    @State private var dossier: DeviceDossier?
    @State private var probing = false

    /// Свой экземпляр контроллера: HAL-чтения дёшевы, актор плеера ради
    /// справки трогать незачем (тот же приём, что у списка устройств).
    private let hal = AudioDeviceController()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if let dossier {
                HStack(alignment: .firstTextBaseline) {
                    DSText(dossier.name, style: .headline)
                    DSText(dossier.transport, style: .label, color: DS.Color.textTertiary)
                    Spacer()
                    Button(probing ? "Probing…" : "Probe exclusive access") { probeHog() }
                        .disabled(probing || playing || dossier.builtIn)
                        .help(
                            dossier.builtIn
                                ? "The built-in output is never hogged"
                                : playing
                                    ? "Stop playback first — the probe takes the device for a moment"
                                    : "Takes exclusive access and immediately gives it back")
                }
                row("Sample rates", Self.rates(dossier.sampleRates))
                row("Bit depths", dossier.bitDepths.map { "\($0)" }.joined(separator: " / "))
                row(
                    "DSD over PCM", dossier.dopCeiling.map { "up to \($0) (DoP)" } ?? "not possible"
                )
                if dossier.nativeDSD {
                    row("Native DSD", "the driver offers a DSD stream format")
                }
                row("Hardware volume", dossier.hardwareVolume ? "yes" : "no knob — fixed output")
                row("Mixer control", dossier.mixingControl ? "can be switched off" : "not exposed")
                row("Exclusive access", hogText)
            } else {
                DSText(
                    "No device to look at — pick an output above.", style: .caption,
                    color: DS.Color.textTertiary)
            }
        }
        .task(id: deviceID) { reload() }
    }

    private var hogText: String {
        guard let dossier else { return "" }
        if dossier.builtIn { return "not used on the built-in output" }
        switch dossier.hogging {
        case .some(true): return "granted"
        case .some(false): return "refused by the device"
        case .none: return "not checked yet"
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            DSText(name, style: .caption, color: DS.Color.textSecondary)
                .frame(width: 130, alignment: .leading)
            DSText(value, style: .caption, lines: 2)
            Spacer()
        }
    }

    private func reload() {
        guard let deviceID else {
            dossier = nil
            return
        }
        Task {
            dossier = try? await hal.dossier(deviceID: deviceID)
        }
    }

    private func probeHog() {
        guard let deviceID else { return }
        probing = true
        Task {
            let granted = await hal.probeHogging(deviceID: deviceID)
            dossier?.hogging = granted
            probing = false
        }
    }

    /// Частоты в килогерцах через POSIX: `formatted()` на русской локали
    /// писал «44,1» (та же ловушка, что в отказе по частоте).
    static func rates(_ rates: [Double]) -> String {
        guard !rates.isEmpty else { return "device reports none" }
        let list = rates.map {
            String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), $0 / 1000)
        }
        return list.joined(separator: " · ") + " kHz"
    }
}

#if DEBUG
private let previewDossier = DeviceDossier(
    name: "FiiO QX13", uid: "preview", transport: "USB",
    sampleRates: [44100, 48000, 88200, 96000, 176_400, 192_000],
    bitDepths: [16, 24, 32], nativeDSD: false, hardwareVolume: true, mixingControl: true,
    builtIn: false, hogging: true)

private struct DossierPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSText(previewDossier.name, style: .headline)
            DSText(DeviceDossierCard.rates(previewDossier.sampleRates), style: .caption)
            DSText(
                previewDossier.dopCeiling.map { "up to \($0) (DoP)" } ?? "not possible",
                style: .caption)
        }
        .padding(DS.Space.xl)
        .frame(width: 460, alignment: .leading)
        .background(DS.Color.bgBase)
    }
}

#Preview("Device dossier — dark") {
    DossierPreview().preferredColorScheme(.dark)
}

#Preview("Device dossier — light") {
    DossierPreview().preferredColorScheme(.light)
}
#endif
