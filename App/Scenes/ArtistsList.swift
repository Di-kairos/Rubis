import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

/// Artists section: artist list in the content column; selection filters albums.
struct ArtistsList: View {
    @Binding var selectedAlbum: Album?
    @Environment(AppEnvironment.self) private var env
    @State private var artists: [Artist] = []
    @State private var selectedArtist: Artist?
    @State private var artistAlbums: [Album] = []

    var body: some View {
        HSplitView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(artists) { artist in
                        DSListRow(
                            isSelected: selectedArtist?.id == artist.id,
                            height: DS.Metrics.sidebarRow
                        ) {
                            DSText(artist.name, style: .body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onTapGesture { select(artist) }
                    }
                }
            }
            .frame(minWidth: 180, maxWidth: 280)

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: DS.Metrics.albumGridCover),
                            spacing: DS.Metrics.albumGridGap)
                    ],
                    spacing: DS.Space.xl
                ) {
                    ForEach(artistAlbums) { album in
                        AlbumCard(album: album, isSelected: selectedAlbum?.id == album.id)
                            .onTapGesture { selectedAlbum = album }
                    }
                }
                .padding(DS.Space.xl)
            }
            .frame(maxWidth: .infinity)
        }
        .background(DS.Color.bgBase)
        .task { reload() }
    }

    private func reload() {
        artists = (try? ArtistRepository(db: env.db).all()) ?? []
        if selectedArtist == nil, let first = artists.first { select(first) }
    }

    private func select(_ artist: Artist) {
        selectedArtist = artist
        guard let id = artist.id else { return }
        artistAlbums = (try? env.albumRepo.albums(byArtist: id)) ?? []
    }
}

/// Tracks section: flat list of everything, double-click plays from that row.
struct TracksList: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tracks: [Track] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    DSListRow(isSelected: isCurrent(track)) {
                        HStack(spacing: DS.Space.md) {
                            DSText(
                                track.title, style: .headline,
                                color: isCurrent(track) ? DS.Color.accent : DS.Color.textPrimary
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            DSText(
                                track.codec.uppercased(), style: .caption,
                                color: DS.Color.textTertiary)
                            DSText(
                                AlbumDetail.format(duration: track.duration), style: .numeric,
                                color: DS.Color.textTertiary)
                        }
                    }
                    .onTapGesture(count: 2) { play(from: index) }
                    .draggable(track.dragPayload)
                }
            }
        }
        .background(DS.Color.bgBase)
        .task {
            tracks = (try? env.trackRepo.recentlyAdded(limit: 5000)) ?? []
        }
    }

    private func isCurrent(_ track: Track) -> Bool {
        if case .playing(let current) = env.playbackState { return current.id == track.id }
        if case .paused(let current) = env.playbackState { return current.id == track.id }
        return false
    }

    private func play(from index: Int) {
        env.play(tracks: tracks, startAt: index)
    }
}

/// Recently Added: album grid ordered by newest tracks.
struct RecentlyAddedGrid: View {
    @Binding var selectedAlbum: Album?
    @Environment(AppEnvironment.self) private var env
    @State private var albums: [Album] = []

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: DS.Metrics.albumGridCover),
                        spacing: DS.Metrics.albumGridGap)
                ],
                spacing: DS.Space.xl
            ) {
                ForEach(albums) { album in
                    AlbumCard(album: album, isSelected: selectedAlbum?.id == album.id)
                        .onTapGesture { selectedAlbum = album }
                }
            }
            .padding(DS.Space.xl)
        }
        .background(DS.Color.bgBase)
        .task {
            albums = (try? env.albumRepo.recentlyAdded()) ?? []
        }
    }
}
