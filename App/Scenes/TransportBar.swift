import AppKit
import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

/// Transport panel (DESIGN §5.1): cover, titles, transport, progress,
/// timings and the quality badge with its popover (SPEC §7.3).
struct TransportBar: View {
    @Environment(AppEnvironment.self) private var env
    @State private var progress: Double = 0
    @State private var timeText = "0:00"
    @State private var totalText = "0:00"
    @State private var showStatusPopover = false

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            DSCoverImage(image: nil, size: DS.Metrics.transportCover)

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

            VStack(spacing: 2) {
                DSProgressBar(progress: progress) { fraction in
                    env.seek(to: fraction)
                }
                HStack {
                    DSText(timeText, style: .numeric, color: DS.Color.textTertiary)
                    Spacer()
                    DSText(totalText, style: .numeric, color: DS.Color.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)

            badge
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Metrics.transportBar)
        .background(DS.Color.bgRaised)
        .onReceive(tick) { _ in refreshTime() }
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
        }
        .padding(DS.Space.lg)
        .frame(width: 280, alignment: .leading)
        .background(DS.Color.bgOverlay)
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
        case .failed(_, let error): return "Error: \(error)"
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
