import AVFAudio
import EscapementCore
import Foundation
import SFBAudioEngine
import Testing
@testable import PlaybackEngine

struct AuditRegressionTests {
    @Test func compensatedCueTimeMustStartAtZero() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let url = try #require(try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil).filter { $0.pathExtension == "flac" }.sorted { $0.path < $1.path }.first)
        let whole = try AudioDecoder(url: url)
        try whole.open()
        let rate = whole.processingFormat.sampleRate
        let region = try #require(CueRegion(track: Track(sourceId: "audit", title: "Audit", duration: 1, codec: "flac", sampleRate: Int(rate), cueStart: 2, cueEnd: 3)))
        let decoder = try region.decoder(url: url)
        if !decoder.isOpen { try decoder.open() }
        print("AUDIT CUE time: framePosition=\(decoder.position), frameLength=\(decoder.length), expected=\(Int(rate))")
        #expect(decoder.position == 0)
        #expect(decoder.length == Int64(rate))
    }
    @Test func shuffleMustKeepDuplicateQueueEntries() {
        let a = PlaybackItem(track: Track(id: 1, sourceId: "audit", title: "A", duration: 5, codec: "flac", sampleRate: 44100), url: URL(fileURLWithPath: "/audit-a.flac"))
        let b = PlaybackItem(track: Track(id: 2, sourceId: "audit", title: "B", duration: 5, codec: "flac", sampleRate: 44100), url: URL(fileURLWithPath: "/audit-b.flac"))
        var random = SystemRandomNumberGenerator()
        let result = PlaybackOrder.shuffled(items: [a,b,a], current: a, mode: .tracks, using: &random)
        print("AUDIT shuffled IDs: \(result.map { $0.track.id })")
        #expect(result.count == 3)
    }
}
