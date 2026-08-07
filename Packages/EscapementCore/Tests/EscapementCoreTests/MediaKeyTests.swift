import Testing

@testable import EscapementCore

struct MediaKeyTests {
    /// Как система пакует нажатие: код клавиши в старшие 16 бит, 0x0A в
    /// байте состояния означает key down, 0x0B — key up.
    private func data1(code: Int, down: Bool) -> Int {
        (code << 16) | ((down ? 0x0A : 0x0B) << 8)
    }

    @Test func recognizesTransportKeys() {
        #expect(MediaKey.from(data1: data1(code: 16, down: true)) == .playPause)
        #expect(MediaKey.from(data1: data1(code: 19, down: true)) == .next)
        #expect(MediaKey.from(data1: data1(code: 20, down: true)) == .previous)
    }

    @Test func ignoresKeyUp() {
        // Иначе одно нажатие сработало бы дважды.
        #expect(MediaKey.from(data1: data1(code: 16, down: false)) == nil)
    }

    @Test func ignoresOtherKeys() {
        // Яркость (21) и громкость (7) — не наше дело.
        #expect(MediaKey.from(data1: data1(code: 21, down: true)) == nil)
        #expect(MediaKey.from(data1: data1(code: 7, down: true)) == nil)
    }
}
