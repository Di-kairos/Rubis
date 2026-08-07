import DesignSystem
import EscapementCore
import SwiftUI

/// Now Playing (SPEC §7.2): текущая очередь воспроизведения.
/// ◆ у играющего трека (D-007), двойной клик или Return — прыжок на трек.
struct NowPlayingQueue: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tracks: [Track] = []
    @State private var currentIndex = 0
    @State private var focused: Int?

    var body: some View {
        Group {
            if tracks.isEmpty {
                DSText(
                    "Queue is empty — play an album or a track",
                    style: .body, color: DS.Color.textTertiary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    // Шапка, чтобы список не выглядел голым (жалоба владельца):
                    // что это за список и сколько в нём.
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        DSText("Now Playing", style: .display)
                        DSText(summary, style: .caption, color: DS.Color.textSecondary)
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.top, DS.Space.xl)
                    queueList
                }
            }
        }
        .background(DS.Color.bgBase)
        .keyboardNavigable(count: tracks.count, index: $focused) { index in
            env.playQueueItem(at: index)
        }
        // Перезагрузка на смене трека; enqueue без смены трека догонит
        // при следующем заходе в раздел.
        .task(id: env.currentTrack?.id) { await reload() }
    }

    private var summary: String {
        let total = tracks.reduce(0) { $0 + $1.duration }
        return "\(tracks.count) tracks · \(AlbumDetail.format(duration: total))"
    }

    private var queueList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        DSListRow(isSelected: focused == index) {
                            HStack(spacing: DS.Space.md) {
                                DSText(
                                    "\(index + 1)", style: .numeric,
                                    color: DS.Color.textTertiary
                                )
                                .frame(width: 24, alignment: .trailing)
                                UnavailableMark(track: track)
                                PlayingMark(isPlaying: index == currentIndex)
                                DSText(
                                    track.title, style: .headline,
                                    color: track.titleColor(
                                        isPlaying: index == currentIndex)
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                DSText(
                                    AlbumDetail.format(duration: track.duration),
                                    style: .numeric, color: DS.Color.textTertiary)
                            }
                        }
                        .id(index)
                        .onTapGesture(count: 2) { env.playQueueItem(at: index) }
                        .onTapGesture { focused = index }
                        .trackQueueMenu(track, env: env)
                    }
                }
            }
            .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
        }
    }

    private func reload() async {
        let snapshot = await env.queueSnapshot()
        tracks = snapshot.tracks
        currentIndex = snapshot.index
    }
}
