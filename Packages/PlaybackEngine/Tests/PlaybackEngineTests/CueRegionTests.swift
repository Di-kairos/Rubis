import AVFAudio
import EscapementCore
import Testing

@testable import PlaybackEngine

struct CueRegionTests {

    private func track(
        start: Double?, end: Double?, sampleRate: Int = 44100, codec: String = "flac"
    ) -> Track {
        Track(
            sourceId: "s", relativePath: "album.flac", title: "Track", duration: 100,
            codec: codec, sampleRate: sampleRate, cueStart: start, cueEnd: end)
    }

    @Test func plainTrackHasNoRegion() {
        #expect(CueRegion(track: track(start: nil, end: nil)) == nil)
    }

    @Test func secondsBecomeFramesOfTheFilesOwnRate() throws {
        let region = try #require(CueRegion(track: track(start: 33, end: 100)))
        #expect(region.startFrame == 33 * 44100)
        #expect(region.frameLength == 67 * 44100)

        let highRate = try #require(
            CueRegion(track: track(start: 33, end: 100, sampleRate: 96000)))
        #expect(highRate.startFrame == 33 * 96000)
    }

    @Test func lastTrackRunsToTheEndOfTheFile() throws {
        let region = try #require(CueRegion(track: track(start: 1140, end: nil)))
        #expect(region.frameLength == -1)
    }

    @Test func fractionalFrameBoundariesAreRounded() throws {
        // 09:22:15 — 562.2 с: на 44.1 кГц это 24 793 020 кадров ровно.
        let region = try #require(CueRegion(track: track(start: 562.2, end: nil)))
        #expect(region.startFrame == 24_793_020)
    }

    @Test func aLyingSheetPlaysToTheEndInsteadOfFailing() throws {
        // Конец раньше начала встречается в самодельных листах.
        let region = try #require(CueRegion(track: track(start: 100, end: 50)))
        #expect(region.frameLength == -1)
        #expect(region.startFrame == 100 * 44100)
    }

    @Test func negativeStartIsClampedToTheBeginning() throws {
        let region = try #require(CueRegion(track: track(start: -5, end: 10)))
        #expect(region.startFrame == 0)
    }
}
