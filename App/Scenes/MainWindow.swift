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
                    .navigationSplitViewColumnWidth(min: 320, ideal: 560)
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
            minHeight: DS.Metrics.windowMinHeight)
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
        switch section {
        case .albums, .nowPlaying, .recentlyAdded:
            AlbumsGrid(selectedAlbum: $selectedAlbum)
        case .artists, .tracks, .playlists:
            // Pack 2 фазы 5: отдельные списки артистов/треков/плейлистов
            DSText("Coming in phase 5 pack 2", style: .body, color: DS.Color.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.bgBase)
        }
    }
}
