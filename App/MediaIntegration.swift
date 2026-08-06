import AppKit
import EscapementCore
import MediaPlayer
import MusicLibrary
import SwiftUI

/// System media integration (SPEC §7.5): Now Playing with cover art and
/// remote/media-key transport commands.
@MainActor
final class MediaIntegration {
    private let env: AppEnvironment
    /// Кэш обложки на альбом — не перечитывать файл на каждом апдейте.
    private var artworkAlbumId: Int64?
    private var artwork: MPMediaItemArtwork?

    init(env: AppEnvironment) {
        self.env = env
        installCommands()
    }

    private func installCommands() {
        // MediaRemote зовёт обработчики на своей очереди — как и у artwork,
        // MainActor-замыкание там означает SIGTRAP. @Sendable + прыжок в
        // MainActor через Task.
        let center = MPRemoteCommandCenter.shared()
        install(center.playCommand) { $0.togglePlayPause() }
        install(center.pauseCommand) { $0.togglePlayPause() }
        install(center.togglePlayPauseCommand) { $0.togglePlayPause() }
        install(center.nextTrackCommand) { $0.next() }
        install(center.previousTrackCommand) { $0.previous() }
    }

    private func install(
        _ command: MPRemoteCommand,
        action: @escaping @MainActor (AppEnvironment) -> Void
    ) {
        command.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                action(self.env)
            }
            return .success
        }
    }

    /// Полное обновление Now Playing (SPEC §7.5 — включая обложку).
    func update() {
        let info = MPNowPlayingInfoCenter.default()
        guard let track = env.currentTrack else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }

        var payload: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyPlaybackRate: env.isPlaying ? 1.0 : 0.0,
        ]
        if let albumId = track.albumId, let album = try? env.albumRepo.album(id: albumId) {
            payload[MPMediaItemPropertyAlbumTitle] = album.title
            payload[MPMediaItemPropertyArtist] = album.albumArtist ?? ""
            payload[MPMediaItemPropertyArtwork] = coverArtwork(album: album)
        }
        info.nowPlayingInfo = payload
        info.playbackState = env.isPlaying ? .playing : .paused
    }

    private func coverArtwork(album: Album) -> MPMediaItemArtwork? {
        if artworkAlbumId == album.id { return artwork }
        artworkAlbumId = album.id
        artwork = nil
        if let hash = album.coverHash,
            let url = env.covers.url(hash: hash, size: 1024),
            let image = NSImage(contentsOf: url)
        {
            // MediaPlayer зовёт обработчик на СВОЕЙ очереди. Замыкание,
            // рождённое в @MainActor-классе, наследует изоляцию — рантайм
            // Swift 6 валит процесс через dispatch_assert_queue (SIGTRAP).
            // @Sendable снимает изоляцию; NSImage — Sendable, картинка из
            // файла immutable, читать её off-main безопасно.
            let cover = image
            artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in cover }
        }
        return artwork
    }
}

extension AppEnvironment {
    var isPlaying: Bool {
        if case .playing = playbackState { return true }
        return false
    }
}
