import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

/// Строка результата поиска. Плоский список поверх групп — по нему ходят стрелки.
private enum SearchItem: Identifiable {
    case artist(Artist)
    case album(Album)
    case track(SearchHit)

    var id: String {
        switch self {
        case .artist(let artist): return "artist-\(artist.id ?? 0)"
        case .album(let album): return "album-\(album.id ?? 0)"
        case .track(let hit): return "track-\(hit.id)"
        }
    }
}

/// FTS search results (SPEC §7.2): живой поиск, группы Artists / Albums / Tracks,
/// ↑↓ ходят по строкам, Enter играет, ⌘Enter кладёт в очередь, Esc сбрасывает поиск.
/// ↓ из поля поиска передаёт фокус сюда (`searchResultsFocusTrigger`).
struct SearchResults: View {
    @Binding var selectedAlbum: Album?
    @Environment(AppEnvironment.self) private var env
    @State private var artists: [Artist] = []
    @State private var albums: [Album] = []
    @State private var hits: [SearchHit] = []
    @State private var focused: Int?
    @FocusState private var listFocused: Bool

    private var items: [SearchItem] {
        artists.map(SearchItem.artist) + albums.map(SearchItem.album)
            + hits.map(SearchItem.track)
    }

    var body: some View {
        let rows = items
        Group {
            if rows.isEmpty {
                DSText("Nothing found", style: .body, color: DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            group("Artists", rows, from: 0, count: artists.count)
                            group("Albums", rows, from: artists.count, count: albums.count)
                            group(
                                "Tracks", rows, from: artists.count + albums.count,
                                count: hits.count)
                        }
                    }
                    .onChange(of: focused) {
                        guard let focused, rows.indices.contains(focused) else { return }
                        proxy.scrollTo(rows[focused].id, anchor: .center)
                    }
                }
            }
        }
        .background(DS.Color.bgBase)
        // Фокусируемся и на «Nothing found» — иначе Esc в этом состоянии мёртв.
        .focusable()
        .focused($listFocused)
        .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape]) { press in
            handle(press, in: rows)
        }
        .onChange(of: env.searchResultsFocusTrigger) {
            listFocused = true
            if focused == nil, !rows.isEmpty { focused = 0 }
        }
        .task(id: env.searchText) {
            // лёгкий дебаунс набора
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let query = env.searchText
            artists = (try? env.artistRepo.search(query)) ?? []
            albums = (try? env.albumRepo.search(query)) ?? []
            hits = (try? env.trackRepo.search(query)) ?? []
            focused = nil
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [SearchItem], from offset: Int, count: Int)
        -> some View
    {
        if count > 0 {
            DSSectionHeader(title)
            ForEach(offset..<(offset + count), id: \.self) { index in
                row(rows[index], at: index, in: rows)
            }
        }
    }

    private func row(_ item: SearchItem, at index: Int, in rows: [SearchItem]) -> some View {
        DSListRow(isSelected: focused == index, height: DS.Metrics.trackRowWithCover) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: icon(item))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    DSText(title(item), style: .headline)
                    if let subtitle = subtitle(item) {
                        DSText(subtitle, style: .caption, color: DS.Color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if case .track(let hit) = item {
                    DSText(
                        AlbumDetail.format(duration: hit.track.duration), style: .numeric,
                        color: DS.Color.textTertiary)
                }
            }
        }
        .id(item.id)
        .onTapGesture { select(item, at: index) }
        .onTapGesture(count: 2) { activate(item, in: rows, queue: false) }
        .contextMenu { QueueMenuItems(tracks: tracks(for: item, in: rows), env: env) }
    }

    // MARK: - Keyboard

    private func handle(_ press: KeyPress, in rows: [SearchItem]) -> KeyPress.Result {
        switch press.key {
        case .escape:
            env.searchText = ""
            return .handled
        case .upArrow, .downArrow:
            guard !rows.isEmpty else { return .ignored }
            let step = press.key == .downArrow ? 1 : -1
            let next = (focused ?? (step > 0 ? -1 : rows.count)) + step
            focused = min(max(next, 0), rows.count - 1)
            return .handled
        case .return:
            guard let focused, rows.indices.contains(focused) else { return .ignored }
            activate(rows[focused], in: rows, queue: press.modifiers.contains(.command))
            return .handled
        default:
            return .ignored
        }
    }

    // MARK: - Actions

    private func select(_ item: SearchItem, at index: Int) {
        focused = index
        listFocused = true
        // Альбом сразу показываем в детали — так же, как клик в сетке.
        if case .album(let album) = item { selectedAlbum = album }
    }

    private func activate(_ item: SearchItem, in rows: [SearchItem], queue: Bool) {
        let selected = tracks(for: item, in: rows)
        guard !selected.isEmpty else { return }
        if queue {
            env.addToQueue(tracks: selected)
            return
        }
        if case .track(let hit) = item {
            // Трек играем в контексте всей группы Tracks — из того же снимка
            // строк, что нарисован, а не из живого `hits` (он мог обновиться).
            let group = rows.compactMap { row -> SearchHit? in
                if case .track(let each) = row { return each }
                return nil
            }
            let start = group.firstIndex { $0.id == hit.id } ?? 0
            env.play(tracks: group.map(\.track), startAt: start)
        } else {
            env.play(tracks: selected)
        }
        if case .album(let album) = item { selectedAlbum = album }
    }

    /// Что кладём в очередь для строки: артист — все его треки, альбом — весь
    /// альбом, трек — он сам.
    private func tracks(for item: SearchItem, in rows: [SearchItem]) -> [Track] {
        switch item {
        case .artist(let artist):
            guard let id = artist.id else { return [] }
            return (try? env.trackRepo.tracks(byArtist: id)) ?? []
        case .album(let album):
            guard let id = album.id else { return [] }
            return (try? env.trackRepo.tracks(inAlbum: id)) ?? []
        case .track(let hit):
            return [hit.track]
        }
    }

    // MARK: - Presentation

    private func icon(_ item: SearchItem) -> String {
        switch item {
        case .artist: return "music.mic"
        case .album: return "square.stack"
        case .track: return "music.note"
        }
    }

    private func title(_ item: SearchItem) -> String {
        switch item {
        case .artist(let artist): return artist.name
        case .album(let album): return album.title
        case .track(let hit): return hit.track.title
        }
    }

    private func subtitle(_ item: SearchItem) -> String? {
        switch item {
        case .artist: return nil
        case .album(let album): return album.year.map(String.init)
        case .track(let hit):
            let parts = [hit.artistName, hit.albumTitle].compactMap(\.self)
            return parts.isEmpty ? nil : parts.joined(separator: " — ")
        }
    }
}
