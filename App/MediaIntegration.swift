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
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.env.togglePlayPause()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.env.togglePlayPause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.env.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.env.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.env.previous()
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
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
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
