import EscapementCore
import Testing

@testable import Rubis_Music

/// Мультивыделение в альбоме и плейлисте: что играет и что уходит в меню
/// определяет порядок списка, а не порядок набора выделения.
struct TrackSelectionTests {
    private let tracks = (1...4).map {
        Track(id: Int64($0), sourceId: "test", title: "T\($0)", duration: 1, codec: "flac", sampleRate: 44100)
    }

    @Test func selectionKeepsListOrder() {
        #expect(tracks.selected(by: [4, 2]).map(\.title) == ["T2", "T4"])
    }

    @Test func playStartsAtTopmostSelectedRow() {
        #expect(tracks.firstSelectedIndex([4, 2]) == 1)
    }

    @Test func emptySelectionPlaysNothing() {
        #expect(tracks.firstSelectedIndex([]) == nil)
        #expect(tracks.selected(by: []).isEmpty)
    }

    @Test func idsOutsideTheListAreIgnored() {
        #expect(tracks.firstSelectedIndex([99]) == nil)
        #expect(tracks.selected(by: [3, 99]).map(\.title) == ["T3"])
    }
}
