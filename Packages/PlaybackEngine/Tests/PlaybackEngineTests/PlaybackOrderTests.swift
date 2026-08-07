import EscapementCore
import Foundation
import Testing

@testable import PlaybackEngine

/// Порядок обхода очереди: перемешивание и переходы.
struct PlaybackOrderTests {
    /// Предсказуемый генератор — тасовка в тестах не должна быть лотереей.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            // xorshift64*
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 2_685_821_657_736_338_717
        }
    }

    private func item(_ id: Int64, album: Int64?) -> PlaybackItem {
        PlaybackItem(
            track: Track(
                id: id, sourceId: "s", relativePath: "\(id).flac", title: "T\(id)",
                albumId: album, duration: 1, codec: "flac", sampleRate: 44_100),
            url: URL(fileURLWithPath: "/tmp/\(id).flac"))
    }

    @Test func shuffleKeepsCurrentFirstAndLosesNothing() {
        let items = (1...20).map { item(Int64($0), album: Int64($0 % 4)) }
        var generator = SeededGenerator(state: 42)
        let shuffled = PlaybackOrder.shuffled(
            items: items, current: items[7], mode: .tracks, using: &generator)

        #expect(shuffled.first?.track.id == items[7].track.id)
        #expect(shuffled.count == items.count)
        #expect(Set(shuffled.map(\.track.id)) == Set(items.map(\.track.id)))
        #expect(shuffled.map(\.track.id) != items.map(\.track.id))
    }

    @Test func albumShuffleKeepsTrackOrderInsideAlbum() {
        // Три альбома по три трека: 1..3 → A, 4..6 → B, 7..9 → C
        let items = (1...9).map { item(Int64($0), album: Int64(($0 - 1) / 3)) }
        var generator = SeededGenerator(state: 7)
        let shuffled = PlaybackOrder.shuffled(
            items: items, current: nil, mode: .albums, using: &generator)

        #expect(shuffled.count == 9)
        for album in Int64(0)...2 {
            let ids = shuffled.filter { $0.track.albumId == album }.compactMap(\.track.id)
            #expect(ids == ids.sorted(), "порядок треков внутри альбома \(album) нарушен")
        }
        // Альбом идёт целиком, без вкраплений чужих треков
        let albumRun = shuffled.map { $0.track.albumId }
        #expect(Set(albumRun).count == 3)
        var runs = 0
        for (position, album) in albumRun.enumerated()
        where position == 0 || albumRun[position - 1] != album {
            runs += 1
        }
        #expect(runs == 3)
    }

    @Test func shuffleOffIsIdentity() {
        let items = (1...5).map { item(Int64($0), album: 1) }
        var generator = SeededGenerator(state: 1)
        let same = PlaybackOrder.shuffled(
            items: items, current: items[0], mode: .off, using: &generator)
        #expect(same.map(\.track.id) == items.map(\.track.id))
    }

    @Test func repeatModesDriveTransitions() {
        #expect(PlaybackOrder.next(after: 2, count: 3, repeatMode: .off) == nil)
        #expect(PlaybackOrder.next(after: 1, count: 3, repeatMode: .off) == 2)
        #expect(PlaybackOrder.next(after: 2, count: 3, repeatMode: .all) == 0)
        #expect(PlaybackOrder.next(after: 1, count: 3, repeatMode: .track) == 1)
        // Кнопка «дальше» не запирает на повторяемом треке
        #expect(PlaybackOrder.manualNext(after: 1, count: 3, repeatMode: .track) == 2)
        #expect(PlaybackOrder.previous(before: 0, count: 3, repeatMode: .off) == nil)
        #expect(PlaybackOrder.previous(before: 0, count: 3, repeatMode: .all) == 2)
        #expect(PlaybackOrder.next(after: 0, count: 0, repeatMode: .all) == nil)
    }
}
