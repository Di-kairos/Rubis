import AppKit
import DesignSystem
import EscapementCore
import SwiftUI

/// Mini player window content (DESIGN §5.7): 240×80, cover + titles +
/// transport, hairline progress along the bottom edge.
struct MiniPlayer: View {
    @Environment(AppEnvironment.self) private var env
    @State private var progress: Double = 0

    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                DSCoverImage(image: coverImage, size: 64, radius: DS.Radius.small)
                VStack(alignment: .leading, spacing: 2) {
                    DSText(env.currentTrack?.title ?? "Nothing playing", style: .headline)
                    HStack(spacing: DS.Space.sm) {
                        DSIconButton(
                            "backward.fill", size: 12, accessibilityLabel: "Previous"
                        ) { env.previous() }
                        DSIconButton(
                            env.isPlaying ? "pause.fill" : "play.fill", size: 16,
                            accessibilityLabel: env.isPlaying ? "Pause" : "Play"
                        ) { env.togglePlayPause() }
                        DSIconButton(
                            "forward.fill", size: 12, accessibilityLabel: "Next"
                        ) { env.next() }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.sm)
            .frame(maxHeight: .infinity)

            DSProgressBar(progress: progress)
        }
        .frame(
            width: DS.Metrics.miniPlayerSize.width,
            height: DS.Metrics.miniPlayerSize.height
        )
        .background(.ultraThinMaterial)
        .onReceive(tick) { _ in refresh() }
    }

    private func refresh() {
        Task {
            if let time = await env.player.playbackTime(), time.total > 0 {
                progress = time.current / time.total
            } else {
                progress = 0
            }
        }
    }

    private var coverImage: NSImage? {
        guard let albumId = env.currentTrack?.albumId,
            let album = try? env.albumRepo.album(id: albumId),
            let hash = album.coverHash,
            let url = env.covers.url(hash: hash, size: 256)
        else { return nil }
        return NSImage(contentsOf: url)
    }
}
