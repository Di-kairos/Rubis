import Foundation
import Testing

@testable import EscapementCore

struct ListeningHistoryTests {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString)/plays.json")
    }

    private func play(
        _ title: String, _ artist: String, album: String = "Album", seconds: Double = 200,
        secondsAgo: TimeInterval = 0
    ) -> PlayEvent {
        PlayEvent(
            date: Date(timeIntervalSince1970: 1_000_000 - secondsAgo), trackId: 1, title: title,
            artist: artist, album: album, seconds: seconds)
    }

    // MARK: - Правило засчёта

    @Test func halfOfTheTrackCounts() {
        #expect(ListeningHistory.counts(listened: 150, duration: 300))
        #expect(!ListeningHistory.counts(listened: 149, duration: 300))
    }

    @Test func fourMinutesCountEvenInALongTrack() {
        // Получасовой сет: половина недостижима за разумное время, четыре
        // минуты — достаточно.
        #expect(ListeningHistory.counts(listened: 240, duration: 1800))
        #expect(!ListeningHistory.counts(listened: 239, duration: 1800))
    }

    @Test func trackWithoutKnownDurationNeedsFourMinutes() {
        #expect(!ListeningHistory.counts(listened: 100, duration: 0))
        #expect(ListeningHistory.counts(listened: 240, duration: 0))
    }

    // MARK: - Сводки

    @Test func topArtistsCountPlaysNotTracks() {
        let top = ListeningHistory.topArtists([
            play("So What", "Miles Davis"),
            play("Blue in Green", "Miles Davis", secondsAgo: 60),
            play("Naima", "John Coltrane"),
        ])
        #expect(top.count == 2)
        #expect(top.first?.name == "Miles Davis")
        #expect(top.first?.count == 2)
        #expect(top.first?.seconds == 400)
        #expect(top.first?.last == Date(timeIntervalSince1970: 1_000_000))
        #expect(top.last?.name == "John Coltrane")
    }

    @Test func sameTitleByDifferentArtistsStaysApart() {
        let top = ListeningHistory.topTracks([
            play("Caravan", "Duke Ellington"),
            play("Caravan", "Art Blakey"),
        ])
        #expect(top.count == 2)
        #expect(Set(top.map(\.detail)) == ["Duke Ellington", "Art Blakey"])
        #expect(top.allSatisfy { $0.name == "Caravan" })
    }

    @Test func topTracksAreCutToTheLimit() {
        let events = (0..<20).map { play("Track \($0)", "Artist") }
        #expect(ListeningHistory.topTracks(events, limit: 5).count == 5)
    }

    @Test func periodFilterDropsOlderPlays() {
        let events = [
            play("Recent", "Artist"),
            play("Old", "Artist", secondsAgo: 10_000),
        ]
        let recent = ListeningHistory.since(
            Date(timeIntervalSince1970: 1_000_000 - 100), in: events)
        #expect(recent.map(\.title) == ["Recent"])
    }

    @Test func emptyHistorySummarisesToNothing() {
        #expect(ListeningHistory.topArtists([]).isEmpty)
        #expect(ListeningHistory.topTracks([]).isEmpty)
    }

    // MARK: - Файл

    @Test func playSurvivesReopening() async {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let history = ListeningHistory(fileURL: file)
        await history.record(
            trackId: 7, title: "So What", artist: "Miles Davis", album: "Kind of Blue",
            seconds: 300)

        let events = await ListeningHistory(fileURL: file).events()
        #expect(events.count == 1)
        #expect(events.first?.trackId == 7)
        #expect(events.first?.artist == "Miles Davis")
    }

    @Test func oldestPlaysFallOffTheLimit() async {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let history = ListeningHistory(fileURL: file, limit: 3)
        for index in 0..<5 {
            await history.record(
                trackId: Int64(index), title: "Track \(index)", artist: "Artist", album: "Album",
                seconds: 200)
        }
        #expect(await history.events().map(\.trackId) == [2, 3, 4])
    }

    @Test func clearingLeavesNothingBehind() async {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let history = ListeningHistory(fileURL: file)
        await history.record(
            trackId: 1, title: "So What", artist: "Miles Davis", album: "Kind of Blue",
            seconds: 300)
        await history.clear()

        #expect(await history.events().isEmpty)
        #expect(await ListeningHistory(fileURL: file).events().isEmpty)
    }
}
