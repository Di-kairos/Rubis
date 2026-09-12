import Testing

@testable import EscapementCore

struct OutputStatusTests {
    private let status = OutputStatus(
        deviceName: "DAC", deviceUID: "uid", deviceSampleRate: 44100, sourceSampleRate: 44100,
        sourceBitDepth: 16, sourceChannels: 2, isExclusive: true, mixingDisabled: true,
        ratePolicy: "nearestFamilyMultiple", isBitPerfect: true)

    @Test func gaplessSeamSwapsTheSourceAndKeepsTheDevice() {
        let next = status.withSource(sampleRate: 44100, bitDepth: 24, channels: 2)
        #expect(next.sourceBitDepth == 24)
        #expect(next.deviceUID == "uid")
        #expect(next.mixingDisabled == true)
        #expect(next.isBitPerfect)
    }

    @Test func unknownBitDepthStaysUnknown() {
        let next = status.withSource(sampleRate: 44100, bitDepth: nil, channels: 2)
        #expect(next.sourceBitDepth == nil)
    }

    @Test func aDifferentRealRateIsNeverBitPerfect() {
        let next = status.withSource(sampleRate: 48000, bitDepth: 16, channels: 2)
        #expect(!next.isBitPerfect)
    }
}
