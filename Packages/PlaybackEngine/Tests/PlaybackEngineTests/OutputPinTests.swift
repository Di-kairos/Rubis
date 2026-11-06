import CoreAudio
import EscapementCore
import Foundation
import SFBAudioEngine
import Synchronization
import Testing

@testable import PlaybackEngine

private let dac = AudioDeviceController.DeviceInfo(id: 104, uid: "usb-dac", name: "USB DAC")
private let speakers = AudioDeviceController.DeviceInfo(id: 92, uid: "built-in", name: "Speakers")

/// Движок, который ведёт себя как AVAudioEngine на macOS: стоит системному
/// выходу по умолчанию смениться — и он уже там, явно заданное устройство
/// не держит.
private final class FollowingEngine: PlaybackEngineDriving, Sendable {
    private let device = Mutex<AudioObjectID>(0)

    var outputDeviceID: AudioObjectID { device.withLock { $0 } }
    func defaultMoved(to id: AudioObjectID) { device.withLock { $0 = id } }

    var nowPlayingID: ObjectIdentifier? { nil }
    var queueIsEmpty: Bool { true }
    var currentTime: TimeInterval? { 0 }
    var totalTime: TimeInterval? { 5 }
    func play(_ decoder: any PCMDecoding) throws {}
    func enqueue(_ decoder: any PCMDecoding) throws {}
    func clearQueue() {}
    @discardableResult func pause() -> Bool { true }
    @discardableResult func resume() -> Bool { true }
    func stop() {}
    @discardableResult func seek(time: TimeInterval) -> Bool { true }
    func setOutputDeviceID(_ id: AudioObjectID) throws { device.withLock { $0 = id } }
    func install(delegate: AnyObject?) {}
}

/// ЦАП — системный выход по умолчанию. Hog уводит default на динамики, как
/// это делает CoreAudio, и движок, следуя за default, уходит туда же.
private final class HoggableDevices: AudioDevicesProviding {
    private let engine: FollowingEngine
    private let current = Mutex(dac)

    init(engine: FollowingEngine) { self.engine = engine }

    func defaultOutputDevice() async throws -> AudioDeviceController.DeviceInfo? {
        current.withLock { $0 }
    }
    func device(uid: String) async throws -> AudioDeviceController.DeviceInfo? { dac }
    func isBuiltInDevice(deviceID: UInt32) async -> Bool { deviceID == speakers.id }
    func startHogging(deviceID: UInt32) async -> Bool {
        current.withLock { $0 = speakers }
        engine.defaultMoved(to: speakers.id)
        return true
    }
    func stopHogging(deviceID: UInt32) async { current.withLock { $0 = dac } }
    func disableMixing(deviceID: UInt32) async -> Bool { true }
    func availableSampleRates(deviceID: UInt32) async throws -> [Double] { [44100, 176400] }
    func physicalFormats(deviceID: UInt32) async throws -> [AudioDeviceController.PhysicalFormat] {
        []
    }
    func nominalSampleRate(deviceID: UInt32) async throws -> Double { 176400 }
    func setNominalSampleRate(deviceID: UInt32, rate: Double) async throws {}
    func hasVolumeControl(deviceID: UInt32) async -> Bool { false }
    func volumeScalar(deviceID: UInt32) async -> Float? { nil }
    func setVolumeScalar(deviceID: UInt32, value: Float) async throws {}
    func observeDeviceDeath(deviceID: UInt32, onDeath: @escaping @Sendable () -> Void) async throws
    {}
    func stopObservingDeviceDeath() async {}
}

/// Живой баг S23: FiiO в hog, бейдж «EXCLUSIVE · FIIO», а звук — в динамиках.
struct OutputPinTests {
    @Test func pinReportsDriftOnlyAwayFromThePinnedDevice() {
        let pin = OutputPin()
        #expect(pin.drift(from: speakers.id) == nil)  // ничего не закреплено
        pin.set(dac.id)
        #expect(pin.drift(from: speakers.id) == dac.id)
        #expect(pin.drift(from: dac.id) == nil)
        pin.set(nil)
        #expect(pin.drift(from: speakers.id) == nil)
    }

    @Test func hoggingTheDefaultDacKeepsTheEngineOnTheDac() async throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        let url = dir.appendingPathComponent("noise-176400-16.flac")
        let engine = FollowingEngine()
        let player = Player(devices: HoggableDevices(engine: engine), engine: engine)
        let track = Track(
            id: 1, sourceId: "s", relativePath: url.lastPathComponent, title: "A",
            duration: 5, codec: "flac", sampleRate: 176400)

        await player.play(items: [PlaybackItem(track: track, url: url)])

        #expect(engine.outputDeviceID == dac.id)
        let status = try #require(await player.outputStatus)
        #expect(status.deviceName == dac.name)
        #expect(status.isExclusive)
        #expect(status.isBitPerfect)
    }
}
