import AppKit
import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

/// Album screen (DESIGN §5.4): cover + metadata left, track list right.
/// `showcase` — режим витрины (Jewel Box II): крупная обложка со «светом
/// витрины» — единственная тень вне поповеров (DESIGN §2.3).
struct AlbumDetail: View {
    let album: Album
    var showcase = false
    /// Размер обложки витрины — витрина считает его от высоты окна.
    var showcaseCover: CGFloat = 240
    @Environment(AppEnvironment.self) private var env
    @State private var tracks: [Track] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            // Обложка рядом с метаданными, пока это влезает; в узкой колонке —
            // друг под другом. Без этого название альбома схлопывалось в «Dea…».
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: DS.Space.xl) {
                    // 240 в витрине: 300 вместе с полкой отжимали у трек-листа
                    // всю высоту на невысоких окнах. В низком окне витрина
                    // присылает размер меньше — иначе экран не влезает целиком.
                    cover(size: showcase ? showcaseCover : 200)
                    metadata
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    cover(size: 140)
                    metadata
                }
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Liner notes (Jewel Box II): многодисковый альбом делится
                    // на секции, трек-лист — с точечными лидерами.
                    ForEach(discs, id: \.no) { disc in
                        if let no = disc.no {
                            DSText(
                                "Disc \(no)", style: .label, color: DS.Color.accent
                            )
                            .padding(.top, DS.Space.lg)
                            .padding(.bottom, DS.Space.xs)
                        }
                        ForEach(disc.rows, id: \.offset) { index, track in
                            trackRow(track, at: index)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.bgBase)
        .task(id: album.id) {
            guard let id = album.id else { return }
            do {
                for try await list in LibraryObservation.tracks(inAlbum: id, db: env.db) {
                    tracks = list
                }
            } catch {
                Log.ui.error("track observation failed: \(error, privacy: .public)")
            }
        }
    }

    /// Строка секции: диск (nil у однодискового альбома) и его треки
    /// с исходными индексами очереди.
    private var discs: [(no: Int?, rows: [(offset: Int, element: Track)])] {
        let indexed = Array(tracks.enumerated())
        let groups = Dictionary(grouping: indexed) { $0.element.discNo ?? 1 }
        guard groups.count > 1 else { return [(no: nil, rows: indexed)] }
        return groups.keys.sorted().map { key in
            (no: key, rows: groups[key] ?? [])
        }
    }

    private func trackRow(_ track: Track, at index: Int) -> some View {
        DSListRow(isSelected: isPlaying(track)) {
            HStack(spacing: DS.Space.md) {
                DSText(
                    "\(track.trackNo ?? index + 1)", style: .numeric,
                    color: DS.Color.textTertiary
                )
                .frame(width: 24, alignment: .trailing)
                UnavailableMark(track: track)
                PlayingMark(isPlaying: isPlaying(track))
                DSText(
                    track.title, style: .headline,
                    color: track.titleColor(isPlaying: isPlaying(track))
                )
                // Лидер сжимается первым: название не обрезается, пока есть место.
                .layoutPriority(1)
                DSDottedLeader()
                DSText(
                    Self.format(duration: track.duration), style: .numeric,
                    color: DS.Color.textTertiary)
            }
        }
        .onTapGesture(count: 2) {
            env.play(album: album, startAt: index)
        }
        .draggable(track.dragPayload)
        .trackQueueMenu(track, env: env)
    }

    /// Название, артист, техстрока и кнопки. Заголовки переносятся на вторую
    /// строку, кнопки держат свою ширину — иначе «Play» обрезался до буквы.
    private var metadata: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSText(album.title, style: .display, lines: 2)
            Text(album.albumArtist ?? "")
                .font(DS.Font.displayArtist)
                .foregroundStyle(DS.Color.accent)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            // Каталожная строка между волосяными линейками — как техпаспорт
            // на конверте (Jewel Box II).
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(DS.Color.strokeHairline).frame(height: 1)
                DSText(metaLine, style: .numeric, color: DS.Color.textTertiary, lines: 2)
                    .padding(.vertical, DS.Space.sm)
                Rectangle().fill(DS.Color.strokeHairline).frame(height: 1)
            }
            .padding(.vertical, DS.Space.xs)
            // Одна тихая кнопка в языке Jewel Box: тонкое золотое кольцо,
            // не залитая плашка (вердикт владельца: заливные кнопки грубые,
            // Shuffle дублировал транспортную панель и удалён).
            Button {
                env.play(album: album)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.accent)
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.vertical, DS.Space.sm)
                    .overlay(Capsule().strokeBorder(DS.Color.accent, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .padding(.top, DS.Space.sm)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        parts.append("\(tracks.count) tracks")
        let total = tracks.reduce(0) { $0 + $1.duration }
        parts.append(Self.format(duration: total))
        if let first = tracks.first {
            parts.append("\(first.codec.uppercased()) \(first.sampleRate / 1000) kHz")
        }
        return parts.joined(separator: " · ")
    }

    private func isPlaying(_ track: Track) -> Bool {
        if case .playing(let current) = env.playbackState { return current.id == track.id }
        if case .paused(let current) = env.playbackState { return current.id == track.id }
        return false
    }

    static func format(duration: Double) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    @ViewBuilder
    private func cover(size: CGFloat) -> some View {
        if showcase {
            DSCoverImage(image: coverImage, size: size, radius: DS.Radius.card)
                .shadow(
                    color: DS.Shadow.showcaseColor,
                    radius: DS.Shadow.showcaseRadius,
                    y: DS.Shadow.showcaseY)
        } else {
            DSCoverImage(image: coverImage, size: size, radius: DS.Radius.card)
        }
    }

    private var coverImage: NSImage? {
        guard let hash = album.coverHash,
            let url = env.covers.url(hash: hash, size: 1024)
        else { return nil }
        return NSImage(contentsOf: url)
    }
}
