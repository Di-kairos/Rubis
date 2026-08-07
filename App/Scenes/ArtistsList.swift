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
    @State private var focused: Int?

    var body: some View {
        HSplitView {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
                            DSListRow(
                                isSelected: selectedArtist?.id == artist.id,
                                height: DS.Metrics.sidebarRow
                            ) {
                                DSText(artist.name, style: .body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            // Клик только двигает фокус: выбор делает onChange,
                            // иначе альбомы артиста грузились бы дважды.
                            .id(artist.id)
                            .onTapGesture { focused = index }
                        }
                    }
                }
                .onChange(of: focused) {
                    guard let focused, artists.indices.contains(focused) else { return }
                    select(artists[focused])
                    proxy.scrollTo(artists[focused].id, anchor: .center)
                }
            }
            .frame(minWidth: 180, maxWidth: 280)
            // Return на артисте играет его целиком.
            .keyboardNavigable(count: artists.count, index: $focused) { index in
                guard let id = artists[index].id else { return }
                env.play(tracks: (try? env.trackRepo.tracks(byArtist: id)) ?? [])
            }

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
