import EscapementCore
import Foundation
import MusicLibrary
import Observation
import PlaybackEngine
import SwiftUI

/// Composition root (SPEC §3.1): the only place where packages meet.
@MainActor
@Observable
final class AppEnvironment {
    let db: AppDatabase
    let player: Player
    let devices: AudioDeviceController
    let scanner: LibraryScanner
    let covers: CoverCache

    var trackRepo: TrackRepository { TrackRepository(db: db) }
    var albumRepo: AlbumRepository { AlbumRepository(db: db) }
    var sourceRepo: SourceRepository { SourceRepository(db: db) }
    var playlistRepo: PlaylistRepository { PlaylistRepository(db: db) }

    // MARK: - Playback state mirrored for SwiftUI

    private(set) var playbackState: PlaybackState = .idle
    private(set) var outputStatus: OutputStatus?
    private(set) var scanProgress: ScanProgress?

    init() throws {
        db = try AppDatabase.standard()
        devices = AudioDeviceController()
        player = Player(devices: devices)
        covers = try CoverCache()
        scanner = LibraryScanner(db: db, covers: covers)

        Task { [player] in
            for await state in await player.stateStream() {
                self.playbackState = state
            }
        }
        Task { [player] in
            for await status in await player.statusStream() {
                self.outputStatus = status
            }
        }
    }

    // MARK: - Intents

    /// Плей всего альбома с выбранной позиции.
    func play(album: Album, startAt index: Int = 0) {
        guard let albumId = album.id else { return }
        Task {
            guard let tracks = try? trackRepo.tracks(inAlbum: albumId) else { return }
            let items = resolveItems(tracks: tracks)
            await player.play(items: items, startAt: index)
        }
    }

    func togglePlayPause() {
        Task { await player.togglePlayPause() }
    }

    func next() {
        Task { await player.next() }
    }

    func previous() {
        Task { await player.previous() }
    }

    func seek(to fraction: Double) {
        Task {
            if let time = await player.playbackTime() {
                await player.seek(to: time.total * fraction)
            }
        }
    }

    /// Track → PlaybackItem: резолв URL через bookmark источника.
    private func resolveItems(tracks: [Track]) -> [PlaybackItem] {
        guard let sources = try? sourceRepo.all() else { return [] }
        let roots: [String: URL] = Dictionary(
            uniqueKeysWithValues: sources.compactMap { source in
                guard let bookmark = source.bookmark,
                    let url = try? LibraryScanner.resolveBookmark(bookmark)
                else { return nil }
                return (source.id, url)
            })
        return tracks.compactMap { track in
            guard let root = roots[track.sourceId], let relative = track.relativePath else {
                return nil
            }
            return PlaybackItem(track: track, url: root.appendingPathComponent(relative))
        }
    }

    // MARK: - Library

    func addFolderSource(url: URL) {
        Task {
            do {
                var source = Source(kind: .local, displayName: url.lastPathComponent)
                source.bookmark = try LibraryScanner.makeBookmark(for: url)
                try sourceRepo.upsert(source)
                try await rescan(source: source)
            } catch {
                Log.library.error("add source failed: \(error, privacy: .public)")
            }
        }
    }

    func rescanAll() {
        Task {
            guard let sources = try? sourceRepo.all() else { return }
            for source in sources where source.kind == .local && source.enabled {
                try? await rescan(source: source)
            }
        }
    }

    private func rescan(source: Source) async throws {
        for try await progress in scanner.scanStream(source: source) {
            scanProgress = progress
        }
        scanProgress = nil
    }
}
