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
    /// Пока писатель сочиняет (10–40 с на новый альбом), полоса не должна
    /// выглядеть пустой — иначе читается как «зависло».
    @State private var notesLoading = false
    /// Свои указатели прокрутки вместо системных скроллбаров — тот же язык,
    /// что у полки альбомов (золотой ползунок в рубиновой оправе).
    @State private var queueScroll = ScrollTrack()
    @State private var queuePosition = ScrollPosition()
    @State private var notesScroll = ScrollTrack()
    @State private var notesPosition = ScrollPosition()

    var body: some View {
        Group {
            if tracks.isEmpty {
                DSText(
                    "Queue is empty — play an album or a track",
                    style: .body, color: DS.Color.textTertiary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Высоты заданы числом, а не «гибкостью»: два скролла в одном
                // VStack SwiftUI делил по своим правилам и очередь схлопывалась
                // в ноль, стоило появиться заметке. GeometryReader убирает
                // переговоры — верхнему ряду достаётся всё, кроме полосы заметок.
                GeometryReader { geo in
                    let band = notes == nil ? 0 : Self.notesHeight + DS.Space.lg
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        // Верх: обложка слева, очередь справа (узкое окно — сверху вниз).
                        Group {
                            if geo.size.width >= 640 {
                                HStack(alignment: .top, spacing: DS.Space.xxl) {
                                    hero
                                    HStack(spacing: DS.Space.sm) {
                                        queueList
                                        verticalIndicator(queueScroll, position: $queuePosition)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: DS.Space.xl) {
                                    hero
                                    HStack(spacing: DS.Space.sm) {
                                        queueList
                                        verticalIndicator(queueScroll, position: $queuePosition)
                                    }
                                }
                            }
                        }
                        .frame(height: max(120, geo.size.height - band))
                        // Низ: liner notes широкой полосой под обеими колонками.
                        notesSection
                    }
                }
                .padding(DS.Space.xl)
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

    /// Liner notes широкой полосой внизу, под обложкой и очередью сразу —
    /// как текст на обороте конверта (вердикт владельца). Высота полосы
    /// ЖЁСТКАЯ: с «потолком» (maxHeight) два гибких скролла в одном VStack
    /// делили высоту как попало и очередь схлопывалась в ноль, стоило
    /// заметке появиться (та же болезнь, что в 0.6.1).
    @ViewBuilder
    private var notesSection: some View {
        if notes == nil, notesLoading {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Rectangle().fill(DS.Color.strokeHairline).frame(height: 1)
                DSText(
                    "Writing liner notes…", style: .label, color: DS.Color.textTertiary
                )
                .padding(.top, DS.Space.sm)
            }
            .frame(height: Self.notesHeight, alignment: .top)
        } else if let notes {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Rectangle().fill(DS.Color.strokeHairline).frame(height: 1)
                HStack(spacing: DS.Space.sm) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: DS.Space.sm) {
                            Text(notes.text.replacingOccurrences(of: "*", with: ""))
                                .font(DS.Font.prose)
                                .foregroundStyle(DS.Color.textSecondary)
                                .lineSpacing(DS.Font.LineSpacing.multiline * 3)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            DSText(notesAttribution, style: .label, color: DS.Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onScrollGeometryChange(for: ScrollTrack.self, of: ScrollTrack.vertical) {
                        _, new in
                        notesScroll = new
                    }
                    .scrollPosition($notesPosition)
                    verticalIndicator(notesScroll, position: $notesPosition)
                }
            }
            .frame(height: Self.notesHeight)
        }
    }

    /// Высота полосы заметок — та же константа в расчёте верхнего ряда.
    private static let notesHeight: CGFloat = 200

    /// Подпись под заметкой: писателя не называем (решение владельца) —
    /// liner notes идут от имени плеера. Wikipedia остаётся названной:
    /// это цитата чужого текста, а не наш.
    private var notesAttribution: String {
        notes?.source == .wikipedia ? "From Wikipedia" : "Rubis Music"
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
            ScrollView(showsIndicators: false) {
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
            }
            .onScrollGeometryChange(for: ScrollTrack.self, of: ScrollTrack.vertical) { _, new in
                queueScroll = new
            }
            .scrollPosition($queuePosition)
            .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
        }
    }

    /// Указатель справа от списка — только когда содержимое не влезло.
    @ViewBuilder
    private func verticalIndicator(
        _ track: ScrollTrack, position: Binding<ScrollPosition>
    ) -> some View {
        if track.visible < 1 {
            DSScrollIndicator(axis: .vertical, progress: track.progress, visible: track.visible) {
                target in
                position.wrappedValue.scrollTo(y: track.offset(forProgress: target))
            }
        } else {
            // Место под указатель держим всегда: иначе текст дёргается вбок,
            // стоит содержимому перевалить за высоту колонки.
            Color.clear.frame(width: DSScrollIndicator.thickness)
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
            notesLoading = true
            notes = await env.albumInfo.info(for: album)
            notesLoading = false
        }
    }
}
