import Foundation
import Testing

@testable import EscapementCore

struct PlaybackSnapshotTests {
    /// Свой suite на тест: настройки приложения не трогаем, а тесты
    /// swift-testing идут параллельно и общий suite затирали бы друг другу.
    private func makeDefaults(_ label: String) -> UserDefaults {
        let name = "playback-snapshot-tests.\(label)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func roundTripKeepsQueueIndexAndOffset() {
        let defaults = makeDefaults("round-trip")
        let snapshot = PlaybackSnapshot(trackIds: [7, 8, 9], index: 1, offset: 42.5)
        snapshot.save(to: defaults)
        #expect(PlaybackSnapshot.load(from: defaults) == snapshot)
    }

    @Test func emptyDefaultsGiveNoSnapshot() {
        #expect(PlaybackSnapshot.load(from: makeDefaults("empty")) == nil)
    }

    @Test func offsetUpdatesWithoutRewritingQueue() {
        let defaults = makeDefaults("offset")
        PlaybackSnapshot(trackIds: [1, 2], index: 0, offset: 0).save(to: defaults)
        PlaybackSnapshot.saveOffset(12.25, to: defaults)
        let loaded = PlaybackSnapshot.load(from: defaults)
        #expect(loaded?.offset == 12.25)
        #expect(loaded?.trackIds == [1, 2])
    }

    @Test func staleIndexIsClampedIntoQueue() {
        let defaults = makeDefaults("clamp")
        PlaybackSnapshot(trackIds: [1, 2, 3], index: 2, offset: 0).save(to: defaults)
        // Очередь укоротилась между запусками — индекс не должен уехать за край.
        PlaybackSnapshot(trackIds: [1], index: 2, offset: 0).save(to: defaults)
        #expect(PlaybackSnapshot.load(from: defaults)?.index == 0)
    }

    @Test func negativeOffsetIsClampedToZero() {
        let defaults = makeDefaults("negative")
        PlaybackSnapshot(trackIds: [1], index: 0, offset: -5).save(to: defaults)
        #expect(PlaybackSnapshot.load(from: defaults)?.offset == 0)
    }
}
