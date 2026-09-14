import EscapementCore
import Foundation
import Testing

@testable import PlaybackEngine

/// Дополнение к `AuditRegressionTests` (аудит 2026-09-12, pack 2): shuffle
/// по вхождениям, а не по идентичности трека.
struct AuditPack2Tests {
    private func item(_ id: Int64, album: Int64? = nil) -> PlaybackItem {
        PlaybackItem(
            track: Track(
                id: id, sourceId: "s", relativePath: "\(id).flac", title: "T\(id)", albumId: album,
                duration: 5, codec: "flac", sampleRate: 44100),
            url: URL(fileURLWithPath: "/tmp/\(id).flac"))
    }

    @Test func shuffleKeepsTheMultisetAndOneCurrentCopy() {
        let a = item(1)
        let b = item(2)
        var random = SystemRandomNumberGenerator()
        for (items, current) in [([a, b, a], 2), ([a, a], 0), ([a, b, a, b], 1)] {
            let order = PlaybackOrder.shuffledIndices(
                items: items, currentIndex: current, mode: .tracks, using: &random)
            #expect(order.count == items.count)
            #expect(order.sorted() == Array(items.indices))
            #expect(order.first == current)
        }
    }

    @Test func albumShuffleKeepsDuplicateOccurrences() {
        let items = [item(1, album: 1), item(2, album: 1), item(1, album: 1), item(3, album: 2)]
        var random = SystemRandomNumberGenerator()
        let order = PlaybackOrder.shuffledIndices(
            items: items, currentIndex: nil, mode: .albums, using: &random)
        #expect(order.sorted() == [0, 1, 2, 3])
    }

    @Test func currentOutsideTheQueueIsIgnored() {
        var random = SystemRandomNumberGenerator()
        let order = PlaybackOrder.shuffledIndices(
            items: [item(1), item(2)], currentIndex: 9, mode: .tracks, using: &random)
        #expect(order.sorted() == [0, 1])
    }
}

/// Транспорт на настоящем `Player` без звука: очередь из несуществующих
/// файлов, устройство — системный выход по умолчанию (нужен только чтобы
/// `prepareDevice` дошёл до своих `await`).
struct AuditPack2PlayerTests {
    /// Без системного выхода `prepareDevice` падает до первого `await` — гонку
    /// проверить нечем; такой стенд тест пропускает молча.
    private func hasOutputDevice() async -> Bool {
        (try? await AudioDeviceController().defaultOutputDevice()) != nil
    }

    private func item(_ id: Int64) -> PlaybackItem {
        PlaybackItem(
            track: Track(
                id: id, sourceId: "s", relativePath: "\(id).flac", title: "T\(id)", duration: 5,
                codec: "flac", sampleRate: 44100),
            url: URL(fileURLWithPath: "/nonexistent/audit-\(id).flac"))
    }

    @Test func shuffleOffReturnsToTheSameOccurrence() async {
        let player = Player(devices: AudioDeviceController())
        let a = item(1)
        let b = item(2)
        await player.restore(items: [a, b, a], at: 2)
        await player.setShuffleMode(.tracks)
        #expect(await player.currentIndex() == 0)
        #expect(await player.queuedItems().count == 3)
        #expect(await player.queuedItems().first == a)
        await player.setShuffleMode(.off)
        #expect(await player.currentIndex() == 2)
        #expect(await player.queuedItems() == [a, b, a])
    }

    @Test func playNextKeepsSourceOrderForShuffleOff() async {
        let player = Player(devices: AudioDeviceController())
        let a = item(1)
        let b = item(2)
        let x = item(9)
        await player.restore(items: [a, b], at: 0)
        await player.playNext(items: [x])
        #expect(await player.queuedItems() == [a, x, b])
        await player.setShuffleMode(.tracks)
        await player.setShuffleMode(.off)
        // База для выключения shuffle — порядок прихода: x пришёл последним.
        #expect(await player.queuedItems() == [a, b, x])
        #expect(await player.currentIndex() == 0)
    }

    @Test func stopDuringStartWins() async throws {
        guard await hasOutputDevice() else { return }
        let player = Player(devices: AudioDeviceController())
        async let start: Void = player.play(items: [item(1)])
        // Старт уже ждёт устройство внутри prepareDevice; стоп его обгоняет.
        try await Task.sleep(for: .milliseconds(20))
        await player.stop()
        await start
        // Стоп — последняя команда, и её состояние остаётся: устаревший старт
        // не имеет права дописать `.failed` (или `.playing`) поверх `.idle`.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await player.state == .idle)
    }

    @Test func secondStartSupersedesTheFirst() async throws {
        guard await hasOutputDevice() else { return }
        let player = Player(devices: AudioDeviceController())
        async let first: Void = player.play(items: [item(1)])
        try await Task.sleep(for: .milliseconds(20))
        await player.play(items: [item(2)])
        await first
        try await Task.sleep(for: .milliseconds(50))
        // Файлов нет — оба старта проваливаются; в состоянии остаётся второй.
        guard case .failed(let track, _) = await player.state else {
            Issue.record("expected .failed, got \(await player.state)")
            return
        }
        #expect(track.id == 2)
    }
}
