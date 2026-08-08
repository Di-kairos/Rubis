import AppKit
import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

/// Витрина альбомов (DESIGN §5.3, Jewel Box II «Витрина»): featured-альбом
/// крупно со «светом витрины» и его трек-лист, остальная коллекция — полкой
/// внизу. Занимает всю площадь окна (двухколонный режим MainWindow).
struct AlbumsShowcase: View {
    /// Featured общий с MainWindow: ⌘L (reveal current) ставит сюда играющий.
    @Binding var featured: Album?
    /// Не-nil — витрина показывает только альбомы этого источника
    /// (клик по источнику в сайдбаре, сессия 05).
    var source: Source?
    @Environment(AppEnvironment.self) private var env
    @State private var albums: [Album] = []
    @State private var focused: Int?

    var body: some View {
        Group {
            if albums.isEmpty {
                DSText(
                    source == nil
                        ? "Drop a music folder here, or add one in Settings (⌘,) → Library"
                        : "No albums in “\(source?.displayName ?? "")” yet — rescan or add music",
                    style: .body,
                    color: DS.Color.textTertiary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    if let featured {
                        AlbumDetail(album: featured, showcase: true)
                            .id(featured.id)
                            // Явный top: дефолтное центрирование обрезало
                            // обложку сверху и выталкивало трек-лист под полку.
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .clipped()
                    }
                    shelf
                }
            }
        }
        .background(DS.Color.bgBase)
        .keyboardNavigable(count: albums.count, horizontal: true, index: $focused) { index in
            env.play(album: albums[index])
        }
        // id: source.id — смена фильтра перезапускает наблюдение.
        .task(id: source?.id) {
            do {
                // Живое наблюдение: витрина обновляется по мере скана.
                let stream = LibraryObservation.albums(db: env.db, sourceId: source?.id)
                for try await list in stream {
                    albums = list
                    ensureFeatured()
                }
            } catch {
                Log.ui.error("album observation failed: \(error, privacy: .public)")
            }
        }
    }

    /// Полка коллекции: горизонтальный ряд обложек на волосяной кромке.
    private var shelf: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.Color.strokeHairline).frame(height: 1)
            ScrollViewReader { proxy in
                // Индикатор видим: без него у полки не было ни одного
                // намёка, что она скроллится (жалоба владельца).
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(alignment: .bottom, spacing: DS.Space.lg) {
                        ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                            shelfCover(album, index: index)
                                .id(album.id)
                        }
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.vertical, DS.Space.lg)
                }
                // Фиксированная высота: без неё горизонтальный скроллер
                // раздувался и отжимал у трек-листа всю высоту (frame=0).
                .frame(height: 108 + DS.Space.lg * 2)
                .onChange(of: focused) {
                    guard let focused, albums.indices.contains(focused) else { return }
                    featured = albums[focused]
                    proxy.scrollTo(albums[focused].id, anchor: .center)
                }
            }
            // Кромка полки — чуть плотнее фоновой линии.
            Rectangle().fill(DS.Color.strokeStrong).frame(height: 1)
        }
    }

    private func shelfCover(_ album: Album, index: Int) -> some View {
        let isFeatured = featured?.id == album.id
        return DSCoverImage(image: shelfImage(album), size: 108, radius: DS.Radius.small)
            // Непроигрываемое приглушено, featured — золотое кольцо (D-007).
            .opacity(isFeatured ? 1 : 0.78)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .strokeBorder(isFeatured ? DS.Color.accent : .clear, lineWidth: 1.5)
            )
            .onTapGesture(count: 2) { env.play(album: album) }
            .onTapGesture { focused = index }
            .help("\(album.title) — \(album.albumArtist ?? "")")
            .accessibilityLabel("\(album.title), \(album.albumArtist ?? "")")
    }

    private func shelfImage(_ album: Album) -> NSImage? {
        guard let hash = album.coverHash,
            let url = env.covers.url(hash: hash, size: 256)
        else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Featured всегда указывает на живой альбом: играющий → прежний → первый.
    private func ensureFeatured() {
        if let current = featured, albums.contains(where: { $0.id == current.id }) { return }
        if let playingId = env.currentTrack?.albumId,
            let playing = albums.first(where: { $0.id == playingId })
        {
            featured = playing
            return
        }
        featured = albums.first
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
