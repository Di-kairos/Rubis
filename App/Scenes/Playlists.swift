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
    /// Выделение треков плейлиста (⌘/⇧-клик, стрелки — от List), как в Tracks.
    @State private var trackSelection: Set<Int64> = []
    @State private var renamingId: Int64?
    @State private var draftName = ""
    /// Поле ввода имени (новый плейлист или переименование) должно получать
    /// курсор само: иначе имя спрашивается, а печатать некуда.
    @FocusState private var nameFieldFocused: Bool
    @State private var focused: Int?
    /// Только что удалённый плейлист и его состав: удаление мгновенное, без
    /// диалога, но восемь секунд его можно вернуть.
    @State private var undo: (name: String, trackIds: [Int64])?
    @State private var undoExpiry: Task<Void, Never>?

    var body: some View {
        HSplitView {
            playlistColumn
                .frame(minWidth: 180, maxWidth: 280)
            trackColumn
                .frame(maxWidth: .infinity)
        }
        .background(DS.Color.bgBase)
        .task(id: env.libraryRevision) {
            reload()
            loadTracks()
        }
        .onChange(of: isEditingName) { env.renamingPlaylist = isEditingName }
        // Заказ нового плейлиста пришёл (⌘⇧N или «Add to Playlist») — пустое
        // имя под курсором.
        .onChange(of: env.pendingNewPlaylistTracks) {
            guard env.pendingNewPlaylistTracks != nil else { return }
            draftName = ""
            nameFieldFocused = true
        }
        // Уходя с раздела в середине ввода имени, не оставляем флаг взведённым —
        // иначе Space и стрелки останутся глобально выключены.
        .onDisappear {
            env.renamingPlaylist = false
            env.pendingNewPlaylistTracks = nil
        }
    }

    // MARK: - Плейлисты

    private var playlistColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                DSSectionHeader("Playlists")
                DSIconButton("plus", accessibilityLabel: "New Playlist") { create() }
            }
            if playlists.isEmpty, env.pendingNewPlaylistTracks == nil {
                DSText("No playlists yet — ⌘⇧N", style: .body, color: DS.Color.textMuted)
                    .padding(DS.Space.md)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if env.pendingNewPlaylistTracks != nil { newPlaylistRow }
                    ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                        playlistRow(playlist)
                            .id(playlist.id)
                            .onTapGesture { focused = index }
                    }
                }
            }
            Spacer(minLength: 0)
            if let undo {
                HStack(spacing: DS.Space.sm) {
                    DSText("Deleted “\(undo.name)”", style: .caption, color: DS.Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Undo") { restoreDeleted() }
                        .font(DS.Font.caption)
                }
                .padding(DS.Space.md)
            }
        }
        .background(DS.Color.bgRaised)
        // Return на плейлисте играет его целиком; во время переименования
        // навигация выключена — клавиши принадлежат текстовому полю.
        .keyboardNavigable(count: isEditingName ? 0 : playlists.count, index: $focused) {
            index in
            guard let id = playlists[index].id,
                let ids = try? env.playlistRepo.trackIds(in: id)
            else { return }
            env.play(tracks: (try? env.trackRepo.tracks(ids: ids)) ?? [])
        }
        .onChange(of: focused) {
            guard let focused, playlists.indices.contains(focused) else { return }
            select(playlists[focused])
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        DSListRow(isSelected: selected?.id == playlist.id, height: DS.Metrics.sidebarRow) {
            if renamingId == playlist.id {
                TextField("", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textPrimary)
                    .focused($nameFieldFocused)
                    .onSubmit { commitRename(playlist) }
            } else {
                DSText(playlist.name, style: .body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

    /// Строка нового плейлиста: в базе его ещё нет, есть только имя под
    /// курсором. Return создаёт, Esc и пустое имя отменяют — плейлиста с
    /// именем-заглушкой не остаётся.
    private var newPlaylistRow: some View {
        DSListRow(isSelected: false, height: DS.Metrics.sidebarRow) {
            TextField("New Playlist", text: $draftName)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
                .focused($nameFieldFocused)
                .onSubmit { commitNew() }
        }
        .onExitCommand { env.pendingNewPlaylistTracks = nil }
    }

    /// Ввод имени открыт — клавиши принадлежат текстовому полю.
    private var isEditingName: Bool {
        renamingId != nil || env.pendingNewPlaylistTracks != nil
    }

    // MARK: - Треки плейлиста

    @ViewBuilder
    private var trackColumn: some View {
        if let playlist = selected {
            List(selection: $trackSelection) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    DSListRow(isSelected: trackSelection.contains(track.id ?? -1)) {
                        HStack(spacing: DS.Space.md) {
                            DSText(
                                "\(index + 1)", style: .numeric, color: DS.Color.textMuted
                            )
                            .frame(width: 24, alignment: .trailing)
                            UnavailableMark(track: track)
                            PlayingMark(isPlaying: isCurrent(track))
                            DSText(
                                track.title, style: .headline,
                                color: track.titleColor(isPlaying: isCurrent(track))
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            DSText(
                                AlbumDetail.format(duration: track.duration), style: .numeric,
                                color: DS.Color.textMuted)
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { env.play(tracks: tracks, startAt: index) }
                    .tag(track.id ?? -1)
                    .plainTrackRow()
                }
                .onMove { source, destination in
                    tracks.move(fromOffsets: source, toOffset: destination)
                    save(in: playlist)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.Color.bgBase)
            // Двойной клик и меню — на уровне списка, как в Tracks: жест на
            // строке съедал одиночные клики. Меню по строке вне выделения
            // получает только её (поведение Finder).
            .contextMenu(forSelectionType: Int64.self) { ids in
                if !ids.isEmpty {
                    QueueMenuItems(tracks: tracks.selected(by: ids), env: env)
                    Divider()
                    Button("Remove from Playlist") { remove(ids: ids, in: playlist) }
                }
            } primaryAction: { ids in
                play(from: ids)
            }
            // Return играет с верхней выделенной строки.
            .onKeyPress(.return) {
                guard !trackSelection.isEmpty else { return .ignored }
                play(from: trackSelection)
                return .handled
            }
            .overlay {
                if tracks.isEmpty {
                    DSText(
                        "Drag tracks here", style: .body, color: DS.Color.textMuted)
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
            DSText("Select a playlist", style: .body, color: DS.Color.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.bgBase)
        }
    }

    // MARK: - Действия

    private func reload() {
        playlists = (try? env.playlistRepo.all()) ?? []
        if selected == nil, let first = playlists.first { select(first) }
    }

    private func create() {
        env.createPlaylist()
    }

    /// Имя введено — только теперь плейлист появляется в базе и открывается.
    private func commitNew() {
        guard let created = env.commitNewPlaylist(named: draftName) else { return }
        reload()
        if let row = playlists.first(where: { $0.id == created.id }) { select(row) }
        focused = playlists.firstIndex { $0.id == created.id }
    }

    private func select(_ playlist: Playlist) {
        selected = playlist
        trackSelection = []
        loadTracks()
    }

    /// Плейлист с верхней выделенной строки — очередь остаётся плейлистом.
    private func play(from ids: Set<Int64>) {
        guard let index = tracks.firstSelectedIndex(ids) else { return }
        env.play(tracks: tracks, startAt: index)
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

    private func remove(ids: Set<Int64>, in playlist: Playlist) {
        tracks = tracks.filter { !ids.contains($0.id ?? -1) }
        trackSelection = []
        save(in: playlist)
    }

    private func delete(_ playlist: Playlist) {
        guard let id = playlist.id else { return }
        let ids = (try? env.playlistRepo.trackIds(in: id)) ?? []
        try? env.playlistRepo.delete(id: id)
        if selected?.id == id {
            selected = nil
            tracks = []
        }
        reload()
        undo = (playlist.name, ids)
        undoExpiry?.cancel()
        undoExpiry = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            undo = nil
        }
    }

    /// Вернуть удалённый плейлист: имя и состав те же, id новый.
    private func restoreDeleted() {
        guard let undo else { return }
        undoExpiry?.cancel()
        self.undo = nil
        guard let created = try? env.playlistRepo.create(name: undo.name),
            let id = created.id
        else { return }
        try? env.playlistRepo.setTracks(undo.trackIds, in: id)
        reload()
        selected = playlists.first { $0.id == id }
        loadTracks()
    }

    private func startRename(_ playlist: Playlist) {
        draftName = playlist.name
        renamingId = playlist.id
        nameFieldFocused = true
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
