import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

/// Sidebar sections (SPEC §7.2).
enum LibrarySection: String, CaseIterable, Identifiable {
    case nowPlaying = "Now Playing"
    case albums = "Albums"
    case artists = "Artists"
    case tracks = "Tracks"
    case recentlyAdded = "Recently Added"
    case playlists = "Playlists"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nowPlaying: return "waveform"
        case .albums: return "square.stack"
        case .artists: return "music.mic"
        case .tracks: return "music.note.list"
        case .recentlyAdded: return "clock"
        case .playlists: return "text.badge.plus"
        }
    }
}

/// Main window: sidebar / content / detail + transport bar (SPEC §7.1).
struct MainWindow: View {
    @Environment(AppEnvironment.self) private var env
    @State private var section: LibrarySection = .albums
    @State private var selectedAlbum: Album?

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                Sidebar(section: $section)
                    .navigationSplitViewColumnWidth(
                        min: DS.Metrics.sidebarWidthMin,
                        ideal: DS.Metrics.sidebarWidth,
                        max: DS.Metrics.sidebarWidthMax)
            } content: {
                sectionContent
                    .navigationSplitViewColumnWidth(min: 240, ideal: 420)
            } detail: {
                if let album = selectedAlbum {
                    AlbumDetail(album: album)
                } else {
                    DSText("Select an album", style: .body, color: DS.Color.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.Color.bgBase)
                }
            }
            Rectangle()
                .fill(DS.Color.strokeHairline)
                .frame(height: 1)
            TransportBar()
        }
        .background(DS.Color.bgBase)
        .frame(
            minWidth: DS.Metrics.windowMinWidth,
            minHeight: DS.Metrics.windowMinHeight
        )
        // ⌘⇧N создаёт плейлист из любого раздела — переключаемся к нему.
        .onChange(of: env.pendingPlaylistId) {
            if env.pendingPlaylistId != nil { section = .playlists }
        }
        // ⌘L: показать альбом играющего трека (SPEC §7.6).
        .onChange(of: env.revealCurrentTrigger) {
            guard let albumId = env.currentTrack?.albumId,
                let album = try? env.albumRepo.album(id: albumId)
            else { return }
            env.searchText = ""
            section = .albums
            selectedAlbum = album
        }
        // Папка из Finder на любое место окна → новый источник (SPEC §7.4 d&d)
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            guard !folders.isEmpty else { return false }
            for folder in folders {
                env.addFolderSource(url: folder)
            }
            return true
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if !env.searchText.isEmpty {
            SearchResults(selectedAlbum: $selectedAlbum)
        } else {
            switch section {
            case .albums, .nowPlaying:
                AlbumsGrid(selectedAlbum: $selectedAlbum)
            case .artists:
                ArtistsList(selectedAlbum: $selectedAlbum)
            case .tracks:
                TracksList()
            case .recentlyAdded:
                RecentlyAddedGrid(selectedAlbum: $selectedAlbum)
            case .playlists:
                PlaylistsView()
            }
        }
    }
}
