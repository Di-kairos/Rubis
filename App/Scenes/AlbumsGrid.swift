import AppKit
import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

/// Album grid (DESIGN §5.3): square covers, two lines, hover play.
struct AlbumsGrid: View {
    @Binding var selectedAlbum: Album?
    @Environment(AppEnvironment.self) private var env
    @State private var albums: [Album] = []
    @State private var focused: Int?

    private let columns = [
        GridItem(
            .adaptive(minimum: DS.Metrics.albumGridCover),
            spacing: DS.Metrics.albumGridGap)
    ]

    var body: some View {
        Group {
            if albums.isEmpty {
                DSText(
                    "Drop a music folder here, or add one in Settings (⌘,) → Library",
                    style: .body,
                    color: DS.Color.textTertiary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: DS.Space.xl) {
                            ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                                AlbumCard(
                                    album: album, isSelected: selectedAlbum?.id == album.id
                                )
                                // Выбор идёт через focused — иначе выделение
                                // назначалось бы дважды за клик.
                                .id(album.id)
                                .onTapGesture { focused = index }
                            }
                        }
                        .padding(DS.Space.xl)
                    }
                    .onChange(of: focused) {
                        guard let focused, albums.indices.contains(focused) else { return }
                        // Стрелки ведут выбор — деталь идёт следом за фокусом.
                        selectedAlbum = albums[focused]
                        proxy.scrollTo(albums[focused].id, anchor: .center)
                    }
                }
            }
        }
        .background(DS.Color.bgBase)
        .keyboardNavigable(count: albums.count, index: $focused) { index in
            env.play(album: albums[index])
        }
        .task {
            // Живое наблюдение: сетка обновляется по мере скана
            do {
                for try await list in LibraryObservation.albums(db: env.db) {
                    albums = list
                }
            } catch {
                Log.ui.error("album observation failed: \(error, privacy: .public)")
            }
        }
    }
}

struct AlbumCard: View {
    let album: Album
    let isSelected: Bool
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ZStack(alignment: .bottomTrailing) {
                DSCoverImage(
                    image: coverImage, size: DS.Metrics.albumGridCover,
                    radius: DS.Radius.card)
                if hovering {
                    Button {
                        env.play(album: album)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(DS.Space.sm)
                    .accessibilityLabel("Play \(album.title)")
                }
            }
            // Выбранный альбом — тонкое золотое кольцо вокруг обложки (D-007).
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .strokeBorder(isSelected ? DS.Color.accent : .clear, lineWidth: 1.5)
            )
            // Приподнимание — тоже движение: с Reduce Motion не двигаем вовсе,
            // а не «двигаем мгновенно».
            .offset(y: hovering && !reduceMotion ? -2 : 0)
            .dsAnimation(DS.Motion.hover, value: hovering)
            DSText(album.title, style: .body)
            DSText(
                album.albumArtist ?? "", style: .caption,
                color: DS.Color.textSecondary)
        }
        .frame(width: DS.Metrics.albumGridCover)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityLabel("\(album.title), \(album.albumArtist ?? "")")
    }

    private var coverImage: NSImage? {
        guard let hash = album.coverHash,
            let url = env.covers.url(hash: hash, size: 256)
        else { return nil }
        return NSImage(contentsOf: url)
    }
}
