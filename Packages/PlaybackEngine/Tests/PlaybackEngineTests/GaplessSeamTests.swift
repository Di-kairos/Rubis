import AVFAudio
import CoreAudio
import EscapementCore
import Foundation
import SFBAudioEngine
import Testing

@testable import PlaybackEngine

/// Слой устройств без CoreAudio: одно устройство, все частоты, никакого hog.
private struct FakeDevices: AudioDevicesProviding {
    static let info = AudioDeviceController.DeviceInfo(id: 1, uid: "fake-dac", name: "Fake DAC")

    func defaultOutputDevice() async throws -> AudioDeviceController.DeviceInfo? { Self.info }
    func device(uid: String) async throws -> AudioDeviceController.DeviceInfo? { Self.info }
    func isBuiltInDevice(deviceID: UInt32) async -> Bool { true }
    func startHogging(deviceID: UInt32) async -> Bool { false }
    func stopHogging(deviceID: UInt32) async {}
    func disableMixing(deviceID: UInt32) async -> Bool { false }
    func availableSampleRates(deviceID: UInt32) async throws -> [Double] {
        [44100, 48000, 88200, 96000, 176400, 192000]
    }
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

/// Движок под управлением теста: звука нет, но видно, что и в каком порядке
/// у него спросили. `activateArmedOnClear` воспроизводит то самое окно —
/// decoding thread забирает заряженный декодер в active ровно между проверкой
/// и `clearQueue`.
private final class FakeEngine: PlaybackEngineDriving, @unchecked Sendable {
    private(set) var playing: (any PCMDecoding)?
    private(set) var queued: [any PCMDecoding] = []
    private(set) var clears = 0
    private(set) var isPaused = false
    var activateArmedOnClear = false
    var currentTime: TimeInterval? = 12.5
    var totalTime: TimeInterval? = 60

    var nowPlayingID: ObjectIdentifier? { playing.map { ObjectIdentifier($0 as AnyObject) } }
    var queueIsEmpty: Bool { queued.isEmpty }

    func play(_ decoder: any PCMDecoding) throws {
        playing = decoder
        queued.removeAll()
        isPaused = false
    }
    func enqueue(_ decoder: any PCMDecoding) throws { queued.append(decoder) }
    func clearQueue() {
        clears += 1
        if activateArmedOnClear, let next = queued.first {
            // Окно гонки: декодер уже ушёл в active, и очистка его не достаёт.
            playing = next
            activateArmedOnClear = false
        }
        queued.removeAll()
    }
    @discardableResult func pause() -> Bool {
        isPaused = true
        return true
    }
    @discardableResult func resume() -> Bool {
        isPaused = false
        return true
    }
    func stop() {
        playing = nil
        queued.removeAll()
    }
    @discardableResult func seek(time: TimeInterval) -> Bool { true }
    func setOutputDeviceID(_ id: AudioObjectID) throws {}
    func install(delegate: AnyObject?) {}

    /// Движок «доиграл» текущий и перешёл на заряженный — как настоящий стык.
    func promoteQueuedToPlaying() {
        guard let next = queued.first else { return }
        playing = next
        queued.removeFirst()
    }
}

private func fixtures() throws -> [URL] {
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures")
    let flacs = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "flac" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    return flacs
}

private func item(_ url: URL, id: Int64, title: String) -> PlaybackItem {
    PlaybackItem(
        track: Track(
            id: id, sourceId: "s", relativePath: url.lastPathComponent, title: title,
            duration: 5, codec: "flac", sampleRate: 176400),
        url: url)
}

/// R03: заряженный переход и правка очереди.
struct GaplessSeamTests {
    private func rig() throws -> (Player, FakeEngine, [PlaybackItem]) {
        let urls = try fixtures()
        let url = try #require(urls.first)
        let engine = FakeEngine()
        let player = Player(devices: FakeDevices(), engine: engine)
        let items = [
            item(url, id: 1, title: "A"), item(url, id: 2, title: "B"),
            item(url, id: 3, title: "X"),
        ]
        return (player, engine, items)
    }

    /// Задержанный callback B плюс Play Next X: движок уже перешёл на
    /// заряженный B, актор об этом ещё не знает, и в этот момент правится
    /// очередь. Публиковать надо заряженное вхождение, а не то, что стало
    /// «следующим» после вставки.
    @Test func transitionPublishesTheArmedEntryNotTheInsertedOne() async throws {
        let (player, engine, items) = try rig()
        await player.play(items: [items[0], items[1]], startAt: 0)
        #expect(await player.state.trackTitle == "A")

        // Движок доиграл A и забрал заряженный B — callback ещё в пути.
        engine.promoteQueuedToPlaying()
        // Пользователь вставляет X сразу после текущего: очередь A→X→B.
        await player.playNext(items: [items[2]])

        let title = await player.state.trackTitle
        #expect(title == "B", "звучит заряженный B — его и показываем")
        #expect(await player.currentIndex() == 2, "B стоит после вставленного X")
    }

    /// Окно между проверкой и очисткой: B ушёл в active, `clearQueue` его не
    /// достал. Тихо зазвучать он не должен — идёт согласованный сброс.
    @Test func decoderThatWentActiveDuringClearForcesAConsistentReset() async throws {
        let (player, engine, items) = try rig()
        await player.play(items: [items[0], items[1]], startAt: 0)
        engine.activateArmedOnClear = true

        await player.playNext(items: [items[2]])

        // Сброс поднял текущий трек заново: звучит именно он, а не B.
        #expect(await player.state.trackTitle == "A")
        #expect(await player.currentIndex() == 0)
        #expect(engine.queueIsEmpty == false, "после сброса заряжен новый следующий")
    }

    /// Правка очереди на паузе звук не включает.
    @Test func editingTheQueueWhilePausedKeepsItPaused() async throws {
        let (player, engine, items) = try rig()
        await player.play(items: [items[0], items[1]], startAt: 0)
        await player.togglePlayPause()
        #expect(await player.state.isPaused)

        engine.activateArmedOnClear = true
        await player.playNext(items: [items[2]])

        #expect(await player.state.isPaused, "после сброса pipeline пауза сохраняется")
        #expect(engine.isPaused)
    }

    /// Repeat на границе меняет, что заряжено, но звук не трогает.
    @Test func repeatModeAtTheSeamRearmsWithoutStartingSound() async throws {
        let (player, engine, items) = try rig()
        await player.play(items: [items[0], items[1]], startAt: 0)
        let clearsBefore = engine.clears

        await player.setRepeatMode(.track)
        #expect(await player.state.trackTitle == "A")
        #expect(engine.clears > clearsBefore, "прежний заряд снят")
        #expect(engine.queueIsEmpty, "repeat track: стык не склеиваем")
    }
}

extension PlaybackState {
    fileprivate var trackTitle: String? {
        switch self {
        case .playing(let track), .paused(let track), .loading(let track): track.title
        default: nil
        }
    }
    fileprivate var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}
