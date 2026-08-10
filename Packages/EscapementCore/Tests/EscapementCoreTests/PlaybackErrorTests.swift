import Testing

@testable import EscapementCore

/// Строка состояния показывает причину словами, а не имя case'а.
struct PlaybackErrorTests {

    @Test func refusalNamesTheDeviceAndTheRate() {
        #expect(
            PlaybackError.rateRefused(source: 192_000, device: "FiiO QX13").errorDescription
                == "Refused: FiiO QX13 cannot do 192 kHz, and resampling is off")
        // 44.1 не должна округлиться до 44
        #expect(
            PlaybackError.rateRefused(source: 44_100, device: "DAC").errorDescription
                == "Refused: DAC cannot do 44.1 kHz, and resampling is off")
    }

    @Test func pinnedDeviceGoneTellsWhereToLook() {
        #expect(
            PlaybackError.deviceUnavailable.errorDescription
                == "Output device is unavailable — pick another in Settings → Audio")
    }

    @Test func everyCaseHasSomethingToShow() {
        let cases: [PlaybackError] = [
            .fileNotFound("x"), .decodingFailed("bad header"), .deviceUnavailable, .deviceLost,
            .rateRefused(source: 48_000, device: "DAC"),
        ]
        for error in cases {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
