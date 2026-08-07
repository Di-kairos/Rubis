import AppKit
import DesignSystem
import EscapementCore
import MusicLibrary
import SwiftUI

/// Album screen (DESIGN §5.4): cover + metadata left, track list right.
struct AlbumDetail: View {
    let album: Album
    @Environment(AppEnvironment.self) private var env
    @State private var tracks: [Track] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            // Обложка рядом с метаданными, пока это влезает; в узкой колонке —
            // друг под другом. Без этого название альбома схлопывалось в «Dea…».
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: DS.Space.xl) {
                    DSCoverImage(image: coverImage, size: 200, radius: DS.Radius.card)
                    metadata
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    DSCoverImage(image: coverImage, size: 140, radius: DS.Radius.card)
                    metadata
                }
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        DSListRow(isSelected: isPlaying(track)) {
                            HStack(spacing: DS.Space.md) {
                                DSText(
                                    "\(track.trackNo ?? index + 1)", style: .numeric,
                                    color: DS.Color.textTertiary
                                )
                                .frame(width: 24, alignment: .trailing)
                                UnavailableMark(track: track)
                                PlayingMark(isPlaying: isPlaying(track))
                                DSText(
                                    track.title, style: .headline,
                                    color: track.titleColor(isPlaying: isPlaying(track))
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                DSText(
                                    Self.format(duration: track.duration), style: .numeric,
                                    color: DS.Color.textTertiary)
                            }
                        }
                        .onTapGesture(count: 2) {
                            env.play(album: album, startAt: index)
                        }
                        .draggable(track.dragPayload)
                        .trackQueueMenu(track, env: env)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.bgBase)
        .task(id: album.id) {
            guard let id = album.id else { return }
            do {
                for try await list in LibraryObservation.tracks(inAlbum: id, db: env.db) {
                    tracks = list
                }
            } catch {
                Log.ui.error("track observation failed: \(error, privacy: .public)")
            }
        }
    }

    /// Название, артист, техстрока и кнопки. Заголовки переносятся на вторую
    /// строку, кнопки держат свою ширину — иначе «Play» обрезался до буквы.
    private var metadata: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSText(album.title, style: .display, lines: 2)
            Text(album.albumArtist ?? "")
                .font(DS.Font.displayArtist)
                .foregroundStyle(DS.Color.accent)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            DSText(metaLine, style: .caption, color: DS.Color.textTertiary, lines: 2)
            HStack(spacing: DS.Space.md) {
                Button {
                    env.play(album: album)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(DS.Font.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Color.accent)
                Button {
                    playShuffled()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(DS.Font.body)
                }
                .buttonStyle(.bordered)
            }
            .fixedSize()
            .padding(.top, DS.Space.sm)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        parts.append("\(tracks.count) tracks")
        let total = tracks.reduce(0) { $0 + $1.duration }
        parts.append(Self.format(duration: total))
        if let first = tracks.first {
            parts.append("\(first.codec.uppercased()) \(first.sampleRate / 1000) kHz")
        }
        return parts.joined(separator: " · ")
    }

    private func isPlaying(_ track: Track) -> Bool {
        if case .playing(let current) = env.playbackState { return current.id == track.id }
        if case .paused(let current) = env.playbackState { return current.id == track.id }
        return false
    }

    private func playShuffled() {
        env.playShuffled(album: album)
    }

    static func format(duration: Double) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    private var coverImage: NSImage? {
        guard let hash = album.coverHash,
            let url = env.covers.url(hash: hash, size: 1024)
        else { return nil }
        return NSImage(contentsOf: url)
    }
}
