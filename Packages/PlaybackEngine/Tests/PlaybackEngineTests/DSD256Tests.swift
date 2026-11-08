import AVFoundation
import CoreAudio
import EscapementCore
import Foundation
import SFBAudioEngine
import Synchronization
import Testing

@testable import PlaybackEngine

/// Живой баг S23: DSD256 DSF не открывался вовсе — апстримный SFBDSFDecoder
/// принимает только DSD64/128. Тест держит пин на форк `0.13.0-rubis.1`:
/// вернись зависимость на апстрим — он упадёт.
struct DSD256Tests {
    /// Минимальный стерео DSF: заголовок, `fmt `, один блок 4096 байт на канал.
    /// ffmpeg DSF не пишет, поэтому файл собирается здесь (спецификация DSF 1.01).
    static func makeDSF(rate: UInt32) throws -> URL {
        let block = 4096
        let channels = 2
        var data = Data()
        func u32(_ v: UInt32) {
            withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
        }
        func u64(_ v: UInt64) {
            withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
        }
        let payload = block * channels
        data.append(contentsOf: Array("DSD ".utf8))
        u64(28)
        u64(UInt64(28 + 52 + 12 + payload))
        u64(0)
        data.append(contentsOf: Array("fmt ".utf8))
        u64(52)
        u32(1)  // format version
        u32(0)  // DSD raw
        u32(2)  // channel type: stereo
        u32(UInt32(channels))
        u32(rate)
        u32(1)  // bits per sample, LSB first
        u64(UInt64(block * 8))  // samples per channel
        u32(UInt32(block))
        u32(0)
        data.append(contentsOf: Array("data".utf8))
        u64(UInt64(12 + payload))
        data.append(Data(repeating: 0x69, count: payload))  // DSD silence pattern
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsd\(rate)-\(UUID().uuidString).dsf")
        try data.write(to: url)
        return url
    }

    @Test func dsd256DsfGoesOutAsDoPAt705k() throws {
        let url = try Self.makeDSF(rate: 11_289_600)
        defer { try? FileManager.default.removeItem(at: url) }

        let dop = try DoPDecoder(decoder: try DSDDecoder(url: url))
        try dop.open()
        #expect(dop.processingFormat.sampleRate == 705_600)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: dop.processingFormat, frameCapacity: 512))
        try dop.decode(into: buffer, length: 512)
        #expect(buffer.frameLength == 512)
    }

    /// Живой баг S23, вторая половина: форк открыл файл, но план не выбрал
    /// DoP — список частот устройства обрезался семействами PCM на 384 кГц,
    /// и 705.6 кГц у FiiO QX13 до проверки не доходил. DSD256 уходил в
    /// PCM-конверсию, которая DSD256 не умеет.
    @Test func dsd256PlansDoPWhenOnlyThePhysicalFormatListsTheRate() async throws {
        let url = try Self.makeDSF(rate: 11_289_600)
        defer { try? FileManager.default.removeItem(at: url) }
        let devices = DoPDevices()
        let player = Player(
            devices: devices,
            configuration: AudioConfiguration(dopConfirmedDeviceUIDs: [DoPDevices.dac.uid]),
            engine: SilentEngine())
        let track = Track(
            id: 1, sourceId: "s", relativePath: url.lastPathComponent, title: "Money",
            duration: 1, codec: "dsf", sampleRate: 11_289_600)

        await player.play(items: [PlaybackItem(track: track, url: url)])

        let status = try #require(await player.outputStatus)
        #expect(status.dsdPath == .dop)
        #expect(devices.rate == 705_600)
        #expect(devices.deepened == [705_600])
    }

    /// Живой баг S23, третья половина: FiiO стоял на 16 бит, DoP-маркеры
    /// обрезались, и ЦАП играл шум. Выбор — 32-бит целое, не 16 и не float.
    @Test func deepestFormatPicksWidestIntegerAtTheRate() throws {
        func pcm(_ rate: Double, _ bits: UInt32, float: Bool = false, ch: UInt32 = 2)
            -> (AudioStreamBasicDescription, ClosedRange<Double>)
        {
            var f = AudioStreamBasicDescription()
            f.mFormatID = kAudioFormatLinearPCM
            f.mFormatFlags = float ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger
            f.mSampleRate = rate
            f.mBitsPerChannel = bits
            f.mChannelsPerFrame = ch
            return (f, rate...rate)
        }
        let fiio = [
            pcm(705_600, 16), pcm(705_600, 32), pcm(44_100, 32), pcm(705_600, 32, float: true),
            pcm(705_600, 32, ch: 8),
        ]
        let best = try #require(
            AudioDeviceController.deepestFormat(in: fiio, at: 705_600, channels: 2))
        #expect(best.mBitsPerChannel == 32)
        #expect(best.mFormatFlags & kAudioFormatFlagIsFloat == 0)
        #expect(best.mChannelsPerFrame == 2)
        #expect(AudioDeviceController.deepestFormat(in: fiio, at: 96_000, channels: 2) == nil)
    }
}

/// FiiO QX13 глазами плеера: номинальные частоты — как их отдаёт
/// `availableSampleRates` (семейства PCM, до 384 кГц), физический формат
/// 705.6 кГц / 32 бит при этом есть.
private final class DoPDevices: AudioDevicesProviding {
    static let dac = AudioDeviceController.DeviceInfo(id: 104, uid: "fiio", name: "FIIO QX13")
    private let current = Mutex<Double>(44_100)
    private let deepenedRates = Mutex<[Double]>([])
    var rate: Double { current.withLock { $0 } }
    var deepened: [Double] { deepenedRates.withLock { $0 } }

    func defaultOutputDevice() async throws -> AudioDeviceController.DeviceInfo? { Self.dac }
    func device(uid: String) async throws -> AudioDeviceController.DeviceInfo? { Self.dac }
    func isBuiltInDevice(deviceID: UInt32) async -> Bool { false }
    func startHogging(deviceID: UInt32) async -> Bool { true }
    func stopHogging(deviceID: UInt32) async {}
    func disableMixing(deviceID: UInt32) async -> Bool { true }
    func availableSampleRates(deviceID: UInt32) async throws -> [Double] {
        [44_100, 48_000, 88_200, 96_000, 176_400, 192_000, 352_800, 384_000]
    }
    func physicalFormats(deviceID: UInt32) async throws -> [AudioDeviceController.PhysicalFormat] {
        [352_800.0, 705_600.0].map {
            AudioDeviceController.PhysicalFormat(
                sampleRates: $0...$0, bitsPerChannel: 32, channels: 2)
        }
    }
    func nominalSampleRate(deviceID: UInt32) async throws -> Double { rate }
    func setNominalSampleRate(deviceID: UInt32, rate: Double) async throws {
        current.withLock { $0 = rate }
    }
    func selectDeepestFormat(deviceID: UInt32, rate: Double) async throws -> Bool {
        deepenedRates.withLock { $0.append(rate) }
        return true
    }
    func hasVolumeControl(deviceID: UInt32) async -> Bool { false }
    func volumeScalar(deviceID: UInt32) async -> Float? { nil }
    func setVolumeScalar(deviceID: UInt32, value: Float) async throws {}
    func observeDeviceDeath(deviceID: UInt32, onDeath: @escaping @Sendable () -> Void) async throws
    {}
    func stopObservingDeviceDeath() async {}
}

private final class SilentEngine: PlaybackEngineDriving, Sendable {
    var outputDeviceID: AudioObjectID { DoPDevices.dac.id }
    var nowPlayingID: ObjectIdentifier? { nil }
    var queueIsEmpty: Bool { true }
    var currentTime: TimeInterval? { 0 }
    var totalTime: TimeInterval? { 1 }
    func play(_ decoder: any PCMDecoding) throws { try decoder.open() }
    func enqueue(_ decoder: any PCMDecoding) throws {}
    func clearQueue() {}
    @discardableResult func pause() -> Bool { true }
    @discardableResult func resume() -> Bool { true }
    func stop() {}
    @discardableResult func seek(time: TimeInterval) -> Bool { true }
    func setOutputDeviceID(_ id: AudioObjectID) throws {}
    func install(delegate: AnyObject?) {}
}
