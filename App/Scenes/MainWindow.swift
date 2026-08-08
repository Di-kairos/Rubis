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
    /// Раздел переживает перезапуск (фаза 7: восстановление состояния).
    @AppStorage("ui.section") private var storedSection: LibrarySection = .albums
    /// Раздел, навязанный замером. Живёт в памяти: DEBUG-прогон не должен
    /// портить сохранённый выбор владельца.
    @State private var forcedSection: LibrarySection? = MainWindow.debugStartSection

    /// Разделы, занимающие всю площадь окна (двухколонный режим, Jewel Box II).
    private var fullBleedSection: Bool {
        section.wrappedValue == .nowPlaying || section.wrappedValue == .albums
    }

    private var section: Binding<LibrarySection> {
        Binding(
            get: { forcedSection ?? storedSection },
            set: { value in
                forcedSection = nil
                storedSection = value
            })
    }
    @State private var selectedAlbum: Album?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            // Now Playing и Albums — фокусные экраны: две колонки, контент
            // занимает всю площадь окна (Jewel Box II). Остальные разделы —
            // три колонки.
            if fullBleedSection, env.searchText.isEmpty {
                NavigationSplitView {
                    Sidebar(section: section)
                        .navigationSplitViewColumnWidth(
                            min: DS.Metrics.sidebarWidthMin,
                            ideal: DS.Metrics.sidebarWidth,
                            max: DS.Metrics.sidebarWidthMax)
                } detail: {
                    if section.wrappedValue == .nowPlaying {
                        NowPlayingQueue()
                    } else {
                        AlbumsShowcase(featured: $selectedAlbum)
                    }
                }
            } else {
                NavigationSplitView {
                    Sidebar(section: section)
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
                            // Ниже этого экран альбома нечитаем: обложка 200 pt
                            // плюс поля не оставляют места под название.
                            .navigationSplitViewColumnWidth(min: 460, ideal: 560)
                    } else {
                        DSText("Select an album", style: .body, color: DS.Color.textTertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(DS.Color.bgBase)
                    }
                }
            }
            Rectangle()
                .fill(DS.Contrast.stroke(increased: contrast == .increased))
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
            if env.pendingPlaylistId != nil { section.wrappedValue = .playlists }
        }
        // ⌘L: показать альбом играющего трека (SPEC §7.6).
        .onChange(of: env.revealCurrentTrigger) {
            guard let albumId = env.currentTrack?.albumId,
                let album = try? env.albumRepo.album(id: albumId)
            else { return }
            env.searchText = ""
            section.wrappedValue = .albums
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

    /// Замеры перекрывают сохранённый раздел: `RUBIS_START_SECTION=Tracks`
    /// открывает приложение сразу на списке. Только DEBUG.
    private static var debugStartSection: LibrarySection? {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["RUBIS_START_SECTION"] else {
            return nil
        }
        return LibrarySection(rawValue: raw)
        #else
        return nil
        #endif
    }

    @ViewBuilder
    private var sectionContent: some View {
        if !env.searchText.isEmpty {
            SearchResults(selectedAlbum: $selectedAlbum)
        } else {
            switch section.wrappedValue {
            case .albums, .nowPlaying:
                // Недостижимо: оба раздела живут в двухколонном режиме выше;
                // сюда попадает только активный поиск (ветка выше).
                DS.Color.bgBase
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
