import AppKit
import DesignSystem
import EscapementCore
import SwiftUI

/// Now Playing (SPEC §7.2): фокусный экран на всю площадь окна — большая
/// обложка играющего альбома слева, очередь воспроизведения справа
/// (решение владельца, сессия 05). ◆ у играющего трека (D-007),
/// двойной клик или Return — прыжок на трек.
struct NowPlayingQueue: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tracks: [Track] = []
    @State private var currentIndex = 0
    @State private var focused: Int?
    @State private var album: Album?
    /// Liner notes (D-008): живут здесь — под hero им самое место
    /// (вердикт владельца: на экране альбома внизу неуместно).
    @AppStorage("albumNotes") private var albumNotes = false
    @State private var notes: AlbumInfo?

    var body: some View {
        Group {
            if tracks.isEmpty {
                DSText(
                    "Queue is empty — play an album or a track",
                    style: .body, color: DS.Color.textTertiary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Широкое окно: обложка слева, очередь справа. Узкое — сверху вниз.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DS.Space.xxl) {
                        hero
                        queueList
                    }
                    .padding(DS.Space.xl)
                    VStack(alignment: .leading, spacing: DS.Space.xl) {
                        hero
                        queueList
                    }
                    .padding(DS.Space.xl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// Играющий альбом крупно — как на экране альбома (DESIGN §5.4),
    /// только про «сейчас звучит».
    private var hero: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            DSCoverImage(image: coverImage, size: 280, radius: DS.Radius.card)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if let track = env.currentTrack {
                    DSText(track.title, style: .display)
                }
                if let album {
                    Text(album.albumArtist ?? "")
                        .font(DS.Font.displayArtist)
                        .foregroundStyle(DS.Color.accent)
                        .lineLimit(2)
                    DSText(album.title, style: .body, color: DS.Color.textSecondary)
                }
                // Сводка очереди между линейками — язык liner notes.
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(DS.Color.strokeHairline).frame(height: 1)
                    DSText(summary, style: .numeric, color: DS.Color.textTertiary)
                        .padding(.vertical, DS.Space.sm)
                    Rectangle().fill(DS.Color.strokeHairline).frame(height: 1)
                }
                .padding(.top, DS.Space.xs)
            }
        }
        .frame(width: 280, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Liner notes на всю ширину колонки очереди, сразу под трек-листом —
    /// скроллятся вместе с ним (вердикт владельца: узкая колонка читалась
    /// «пятном», текст должен идти широко и органично).
    @ViewBuilder
    private var notesSection: some View {
        if let notes {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Rectangle().fill(DS.Color.strokeHairline).frame(height: 1)
                    .padding(.top, DS.Space.lg)
                Text(notes.text.replacingOccurrences(of: "*", with: ""))
                    .font(DS.Font.prose)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineSpacing(DS.Font.LineSpacing.multiline * 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                DSText(
                    notes.source == .wikipedia ? "From Wikipedia" : "Notes by Claude",
                    style: .label, color: DS.Color.textTertiary)
            }
            .padding(.top, DS.Space.sm)
        }
    }

    private var coverImage: NSImage? {
        guard let hash = album?.coverHash,
            let url = env.covers.url(hash: hash, size: 256)
        else { return nil }
        return NSImage(contentsOf: url)
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
                                .layoutPriority(1)
                                DSDottedLeader()
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
                notesSection
            }
            .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
        }
    }

    private func reload() async {
        let snapshot = await env.queueSnapshot()
        tracks = snapshot.tracks
        currentIndex = snapshot.index
        if let albumId = env.currentTrack?.albumId {
            album = try? env.albumRepo.album(id: albumId)
        } else {
            album = nil
        }
        notes = nil
        if albumNotes, let album {
            notes = await env.albumInfo.info(for: album)
        }
    }
}
