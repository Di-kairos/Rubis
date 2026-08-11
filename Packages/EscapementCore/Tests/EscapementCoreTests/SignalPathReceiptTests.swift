import Foundation
import Testing

@testable import EscapementCore

struct SignalPathReceiptTests {

    private func receipt(
        sourceRate: Double = 44100, deviceRate: Double = 44100, exclusive: Bool = true,
        bitPerfect: Bool = true
    ) -> SignalPathReceipt {
        SignalPathReceipt(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "0.8.9 (26)", track: "Agos — Sebastian Plano", codec: "flac",
            sourceRate: sourceRate, sourceBits: 24, channels: 2, deviceName: "FiiO QX13",
            deviceTransport: "USB", deviceRate: deviceRate, exclusive: exclusive,
            mixingDisabled: true, dsd: nil, fallback: "Nearest family multiple",
            bitPerfect: bitPerfect)
    }

    @Test func bitPerfectPathSaysSo() {
        let text = receipt().rendered()
        #expect(text.contains("Bit-perfect — the file reaches the DAC unchanged"))
        #expect(text.contains("FLAC · 44.1 kHz · 24 bit · 2 ch"))
        #expect(text.contains("FiiO QX13 (USB)"))
    }

    @Test func resamplingIsNamedBeforeSharedOutput() {
        // Обе беды сразу: сначала называем ту, что портит звук сильнее.
        let text = receipt(deviceRate: 48000, exclusive: false, bitPerfect: false).rendered()
        #expect(text.contains("Resampled — the device is running at a different rate"))
    }

    @Test func sharedOutputIsExplained() {
        let text = receipt(exclusive: false, bitPerfect: false).rendered()
        #expect(text.contains("Shared — CoreAudio mixes this output with other apps"))
        #expect(text.contains("Exclusive    no"))
    }

    @Test func ratesUseAPosixDecimalPoint() {
        // На русской локали `formatted()` писал «44,1» — отчёт должен читаться
        // одинаково в любом чате.
        #expect(SignalPathReceipt.khz(44100) == "44.1 kHz")
        #expect(SignalPathReceipt.khz(192_000) == "192 kHz")
    }

    @Test func fingerprintChangesWithTheSmallestEdit() {
        let original = receipt().rendered()
        let tampered = original.replacingOccurrences(of: "24 bit", with: "32 bit")
        let body = { (text: String) in
            text.split(separator: "\n").dropLast().joined(separator: "\n")
        }
        #expect(
            SignalPathReceipt.fingerprint(of: body(original))
                != SignalPathReceipt.fingerprint(of: body(tampered)))
    }

    @Test func fingerprintIsStableForTheSameText() {
        #expect(
            SignalPathReceipt.fingerprint(of: "signal path")
                == SignalPathReceipt.fingerprint(of: "signal path"))
    }

    @Test func receiptWithoutATrackStillDescribesTheDevice() {
        var idle = receipt()
        idle.track = nil
        let text = idle.rendered()
        #expect(!text.contains("Track"))
        #expect(text.contains("Device"))
    }
}
