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
    /// Заметки включены, но их нет — строкой, почему именно.
    @State private var notesMissing: String?
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
                    let notesHeight = notesHeight(in: geo.size.height)
                    let gap = notesHeight > 0 ? DS.Space.lg : 0
                    let rowHeight = max(Self.rowMinHeight, geo.size.height - notesHeight - gap)
                    let cover = Self.coverSize(rowHeight: rowHeight)
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        // Верх: обложка слева, очередь справа (узкое окно — сверху вниз).
                        Group {
                            if geo.size.width >= 640 {
                                HStack(alignment: .top, spacing: DS.Space.xxl) {
                                    hero(cover: cover)
                                    HStack(spacing: DS.Space.sm) {
                                        queueList
                                        verticalIndicator(queueScroll, position: $queuePosition)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: DS.Space.xl) {
                                    hero(cover: cover)
                                    HStack(spacing: DS.Space.sm) {
                                        queueList
                                        verticalIndicator(queueScroll, position: $queuePosition)
                                    }
                                }
                            }
                        }
                        .frame(height: rowHeight)
                        // Низ: liner notes широкой полосой под обеими колонками.
                        notesSection(height: notesHeight)
                    }
                }
                .padding(DS.Space.xl)
            }
        }
        .background(DS.Color.bgBase)
        .keyboardNavigable(count: tracks.count, index: $focused) { index in
            env.playQueueItem(at: index)
        }
        // Перезагрузка на смене трека и на тихом восстановлении очереди: restore
        // оставляет playbackState idle, поэтому currentTrack сам не меняется.
        .task(id: reloadID) { await reload() }
    }

    /// Играющий альбом крупно — как на экране альбома (DESIGN §5.4),
    /// только про «сейчас звучит». Обложка и шрифты идут за высотой окна:
    /// в низком окне блок ужимается целиком, а не вылезает на заметки.
    private func hero(cover: CGFloat) -> some View {
        // Ниже этого размера крупный кегль перестаёт быть уместным —
        // заголовок звучит громче обложки, которая уже с ноготь.
        let compact = cover < 200
        return VStack(alignment: .leading, spacing: compact ? DS.Space.sm : DS.Space.lg) {
            DSCoverImage(image: coverImage, size: cover, radius: DS.Radius.card)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if let track = displayTrack {
                    DSText(track.title, style: compact ? .title : .display, lines: compact ? 1 : 2)
                }
                if let album {
                    Text(album.albumArtist ?? "")
                        .font(compact ? DS.Font.headline : DS.Font.displayArtist)
                        .foregroundStyle(DS.Color.accent)
                        .lineLimit(compact ? 1 : 2)
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
        .frame(width: cover, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Liner notes широкой полосой внизу, под обложкой и очередью сразу —
    /// как текст на обороте конверта (вердикт владельца). Высота приходит
    /// сверху числом: с «потолком» (maxHeight) два гибких скролла в одном
    /// VStack делили высоту как попало и очередь схлопывалась в ноль, стоило
    /// заметке появиться (та же болезнь, что в 0.6.1).
    @ViewBuilder
    private func notesSection(height: CGFloat) -> some View {
        if notes == nil, notesLoading {
            notice("Writing liner notes…")
        } else if notes == nil, let notesMissing {
            // Включённые заметки, которых нет, раньше оставляли пустое место
            // без единого слова — и это читалось как поломка.
            notice(notesMissing)
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
            .frame(height: height)
        }
    }

    /// Одна строка под чертой: «пишем…» или почему заметки нет.
    private func notice(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Rectangle().fill(DS.Color.strokeHairline).frame(height: 1)
            DSText(text, style: .label, color: DS.Color.textTertiary)
                .padding(.top, DS.Space.sm)
        }
        .frame(height: Self.noticeHeight, alignment: .top)
    }

    /// Потолок полосы заметок в высоком окне.
    private static let notesMaxHeight: CGFloat = 200
    /// Полоса под одну строку: раньше «пишем…» занимало все 200 pt, а верхний
    /// ряд об этом не знал — и очередь уезжала под черту.
    private static let noticeHeight: CGFloat = 44
    /// Ниже этого верхний ряд не ужимается — дальше сжимать нечего.
    private static let rowMinHeight: CGFloat = 200
    /// Что резервируем под заголовок, артиста, альбом и сводку под обложкой.
    private static let heroTextHeight: CGFloat = 170

    /// Заметка забирает долю высоты, а не жёсткие 200 pt: в низком окне
    /// полоса ужимается вместе со всем остальным, а не выдавливает hero.
    private func notesHeight(in available: CGFloat) -> CGFloat {
        if notes != nil { return min(Self.notesMaxHeight, max(90, available * 0.3)) }
        if notesLoading || notesMissing != nil { return Self.noticeHeight }
        return 0
    }

    /// Обложка идёт за высотой ряда: 280 pt в просторном окне, до 120 —
    /// в тесном. Ширина колонки hero равна обложке, поэтому вместе с ней
    /// сужается и текстовый блок.
    static func coverSize(rowHeight: CGFloat) -> CGFloat {
        min(280, max(120, rowHeight - heroTextHeight))
    }

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

    private var reloadID: String {
        "\(env.queueRevision):\(env.currentTrack?.id ?? -1)"
    }

    private var displayTrack: Track? {
        env.currentTrack ?? currentQueueTrack
    }

    private var currentQueueTrack: Track? {
        tracks.indices.contains(currentIndex) ? tracks[currentIndex] : nil
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
        let current =
            snapshot.tracks.indices.contains(snapshot.index)
            ? snapshot.tracks[snapshot.index]
            : env.currentTrack
        if let albumId = current?.albumId {
            album = try? env.albumRepo.album(id: albumId)
        } else {
            album = nil
        }
        notes = nil
        notesMissing = nil
        if albumNotes, let album {
            notesLoading = true
            notes = await env.albumInfo.info(for: album)
            notesLoading = false
            if notes == nil {
                let writer = AlbumInfoService.selectedProvider.displayName
                notesMissing =
                    await env.albumInfo.writerKeyIsSet()
                    ? "No liner notes: nothing in Wikipedia, and \(writer) had nothing to add"
                    : "No liner notes: nothing in Wikipedia, and no \(writer) key is set "
                        + "— Settings → Album notes"
            }
        }
    }
}
