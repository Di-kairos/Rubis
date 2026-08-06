import Testing

@testable import PlaybackEngine

struct SampleRatePolicyTests {
    let dacRates = [44100.0, 48000.0, 88200.0, 96000.0, 176400.0, 192000.0]

    @Test func exactMatchWins() {
        #expect(
            SampleRatePolicy.choose(source: 192000, available: dacRates, fallback: .refuse)
                == .exact(192000))
    }

    @Test func familyMultipleAboveIsPreferred() {
        // Device without 352.8k: DSD-derived 352.8k source → nothing above in family,
        // largest below wins (176.4), never the 48k family.
        #expect(
            SampleRatePolicy.choose(
                source: 352800, available: dacRates, fallback: .nearestFamilyMultiple)
                == .familyMultiple(176400))
    }

    @Test func smallestMultipleAboveBeatsLargerOnes() {
        // 44.1 source on a device with only 88.2 and 176.4: takes 88.2.
        #expect(
            SampleRatePolicy.choose(
                source: 44100, available: [88200, 176400, 96000],
                fallback: .nearestFamilyMultiple)
                == .familyMultiple(88200))
    }

    @Test func crossFamilyOnlyWhenAllowed() {
        // 44.1-family source on a 48-only device.
        let available = [48000.0, 96000.0, 192000.0]
        #expect(
            SampleRatePolicy.choose(
                source: 88200, available: available, fallback: .nearestFamilyMultiple)
                == .refuse)
        #expect(
            SampleRatePolicy.choose(
                source: 88200, available: available, fallback: .allowCrossFamily)
                == .crossFamily(192000))
    }

    @Test func refusePolicyRefusesOnMismatch() {
        #expect(
            SampleRatePolicy.choose(source: 352800, available: dacRates, fallback: .refuse)
                == .refuse)
    }

    @Test func emptyDeviceListRefuses() {
        #expect(
            SampleRatePolicy.choose(source: 44100, available: [], fallback: .allowCrossFamily)
                == .refuse)
    }

    @Test func nonFamilyRateFallsThroughToCrossFamily() {
        // Exotic source rate outside both families (e.g. 32000).
        #expect(
            SampleRatePolicy.choose(
                source: 32000, available: dacRates, fallback: .nearestFamilyMultiple)
                == .refuse)
        #expect(
            SampleRatePolicy.choose(
                source: 32000, available: dacRates, fallback: .allowCrossFamily)
                == .crossFamily(192000))
    }
}
