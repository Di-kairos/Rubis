import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

extension Track {
    /// Полезная нагрузка перетаскивания трека — id строкой (SPEC §7.4 d&d).
    var dragPayload: String { id.map(String.init) ?? "" }
}

/// Playlists section: playlist column + ordered track list with drag & drop.
struct PlaylistsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var playlists: [Playlist] = []
    @State private var selected: Playlist?
    @State private var tracks: [Track] = []
    @State private var renamingId: Int64?
    @State private var draftName = ""

    var body: some View {
        HSplitView {
            playlistColumn
                .frame(minWidth: 180, maxWidth: 280)
            trackColumn
                .frame(maxWidth: .infinity)
        }
        .background(DS.Color.bgBase)
        .task { reload() }
    }

    // MARK: - Плейлисты

    private var playlistColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                DSSectionHeader("Playlists")
                DSIconButton("plus", accessibilityLabel: "New Playlist") { create() }
            }
            if playlists.isEmpty {
                DSText("No playlists yet — ⌘⇧N", style: .body, color: DS.Color.textTertiary)
                    .padding(DS.Space.md)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(playlists) { playlist in
                        playlistRow(playlist)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .background(DS.Color.bgRaised)
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        DSListRow(isSelected: selected?.id == playlist.id, height: DS.Metrics.sidebarRow) {
            if renamingId == playlist.id {
                TextField("", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textPrimary)
                    .onSubmit { commitRename(playlist) }
            } else {
                DSText(playlist.name, style: .body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onTapGesture { select(playlist) }
        .contextMenu {
            Button("Rename") { startRename(playlist) }
            Button("Delete") { delete(playlist) }
        }
        // Трек из библиотеки → в конец плейлиста
        .dropDestination(for: String.self) { payload, _ in
            guard let id = playlist.id else { return false }
            let ids = payload.compactMap(Int64.init)
            guard !ids.isEmpty, (try? env.playlistRepo.append(ids, to: id)) != nil else {
                return false
            }
            if selected?.id == id { loadTracks() }
            return true
        }
    }

    // MARK: - Треки плейлиста

    @ViewBuilder
    private var trackColumn: some View {
        if let playlist = selected {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    DSListRow(isSelected: isCurrent(track)) {
                        HStack(spacing: DS.Space.md) {
                            DSText(
                                "\(index + 1)", style: .numeric, color: DS.Color.textTertiary
                            )
                            .frame(width: 24, alignment: .trailing)
                            UnavailableMark(track: track)
                            DSText(
                                track.title, style: .headline,
                                color: track.titleColor(isPlaying: isCurrent(track))
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            DSText(
                                AlbumDetail.format(duration: track.duration), style: .numeric,
                                color: DS.Color.textTertiary)
                        }
                    }
                    .onTapGesture(count: 2) { env.play(tracks: tracks, startAt: index) }
                    .contextMenu {
                        Button("Remove from Playlist") { remove(at: index, in: playlist) }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(DS.Color.bgBase)
                }
                .onMove { source, destination in
                    tracks.move(fromOffsets: source, toOffset: destination)
                    save(in: playlist)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.Color.bgBase)
            .overlay {
                if tracks.isEmpty {
                    DSText(
                        "Drag tracks here", style: .body, color: DS.Color.textTertiary)
                }
            }
            .dropDestination(for: String.self) { payload, _ in
                guard let id = playlist.id else { return false }
                let ids = payload.compactMap(Int64.init)
                guard !ids.isEmpty, (try? env.playlistRepo.append(ids, to: id)) != nil else {
                    return false
                }
                loadTracks()
                return true
            }
        } else {
            DSText("Select a playlist", style: .body, color: DS.Color.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.bgBase)
        }
    }

    // MARK: - Действия

    private func reload() {
        playlists = (try? env.playlistRepo.all()) ?? []
        // ⌘⇧N мог создать плейлист до появления этого экрана — открываем его.
        if let pending = env.pendingPlaylistId {
            env.pendingPlaylistId = nil
            if let created = playlists.first(where: { $0.id == pending }) {
                select(created)
                startRename(created)
                return
            }
        }
        if selected == nil, let first = playlists.first { select(first) }
    }

    private func create() {
        env.createPlaylist()
        reload()
    }

    private func select(_ playlist: Playlist) {
        selected = playlist
        loadTracks()
    }

    private func loadTracks() {
        guard let id = selected?.id,
            let ids = try? env.playlistRepo.trackIds(in: id)
        else {
            tracks = []
            return
        }
        tracks = (try? env.trackRepo.tracks(ids: ids)) ?? []
    }

    private func save(in playlist: Playlist) {
        guard let id = playlist.id else { return }
        try? env.playlistRepo.setTracks(tracks.compactMap(\.id), in: id)
    }

    private func remove(at index: Int, in playlist: Playlist) {
        tracks.remove(at: index)
        save(in: playlist)
    }

    private func delete(_ playlist: Playlist) {
        guard let id = playlist.id else { return }
        try? env.playlistRepo.delete(id: id)
        if selected?.id == id {
            selected = nil
            tracks = []
        }
        reload()
    }

    private func startRename(_ playlist: Playlist) {
        draftName = playlist.name
        renamingId = playlist.id
    }

    private func commitRename(_ playlist: Playlist) {
        renamingId = nil
        guard let id = playlist.id, !draftName.isEmpty else { return }
        try? env.playlistRepo.rename(id: id, to: draftName)
        reload()
    }

    private func isCurrent(_ track: Track) -> Bool {
        if case .playing(let current) = env.playbackState { return current.id == track.id }
        if case .paused(let current) = env.playbackState { return current.id == track.id }
        return false
    }
}
