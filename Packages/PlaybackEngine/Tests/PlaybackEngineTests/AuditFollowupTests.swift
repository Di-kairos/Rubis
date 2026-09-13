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
// Доступ строго последовательный: тест меняет модель только между завершёнными
// await-вызовами Player; install не запускает фоновых callbacks.
private final class FakeEngine: PlaybackEngineDriving, @unchecked Sendable {
    private(set) var playing: (any PCMDecoding)?
    private(set) var queued: [any PCMDecoding] = []
    private(set) var active: [any PCMDecoding] = []
    private(set) var playCalls = 0
    private(set) var clears = 0
    private(set) var isPaused = false
    var activateArmedOnClear = false
    var currentTime: TimeInterval? = 0.5
    var totalTime: TimeInterval? = 5

    var nowPlayingID: ObjectIdentifier? { playing.map { ObjectIdentifier($0 as AnyObject) } }
    var queueIsEmpty: Bool { queued.isEmpty }

    func play(_ decoder: any PCMDecoding) throws {
        playing = decoder
        playCalls += 1
        active.removeAll()
        queued.removeAll()
        isPaused = false
    }
    func enqueue(_ decoder: any PCMDecoding) throws { queued.append(decoder) }
    func clearQueue() {
        clears += 1
        if activateArmedOnClear, let next = queued.first {
            // Окно гонки: декодер уже ушёл в active, и очистка его не достаёт.
            active.append(next)
            activateArmedOnClear = false
            if decodeOnActivate,
                let buffer = AVAudioPCMBuffer(pcmFormat: next.processingFormat, frameCapacity: 1024)
            {
                try? next.decode(into: buffer, length: 1024)
                leakedFrames += Int(buffer.frameLength)
            }
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
        active.removeAll()
        queued.removeAll()
    }
    @discardableResult func seek(time: TimeInterval) -> Bool { true }
    func setOutputDeviceID(_ id: AudioObjectID) throws {}
    func install(delegate: AnyObject?) {}

    /// Decoding thread движка: каждому active-декодеру даётся декодировать блок.
    /// Отозванный отдаёт ноль кадров — движок считает его законченным и убирает
    /// из active, как настоящий SFB после `decodingComplete`. `decodeOnActivate`
    /// моделирует заряд, который успел положить кадры в кольцевой буфер ДО
    /// правки очереди.
    var decodeOnActivate = false
    private(set) var leakedFrames = 0

    func pumpDecoding() {
        active = active.filter { decoder in
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: decoder.processingFormat, frameCapacity: 1024)
            else { return false }
            try? decoder.decode(into: buffer, length: 1024)
            return buffer.frameLength > 0
        }
    }

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
    let flacs = try FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil
    )
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

/// Следующий уже декодируется, но текущий ещё звучит: это разные состояния SFB.
struct AuditFollowupTests {
    @Test func activeFutureDecoderMustBeFlushedEvenWhileNowPlayingIsStillA() async throws {
        let url = try #require(try fixtures().first)
        let engine = FakeEngine()
        let player = Player(devices: FakeDevices(), engine: engine)
        let a = item(url, id: 1, title: "A")
        let b = item(url, id: 2, title: "B")
        let x = item(url, id: 3, title: "X")
        await player.play(items: [a, b], startAt: 0)
        let oldPlaying = engine.nowPlayingID
        let preparedB = try #require(engine.queued.first)
        let bID = ObjectIdentifier(preparedB as AnyObject)
        engine.activateArmedOnClear = true
        await player.playNext(items: [x])
        // Decoding thread добирается до B уже после отзыва: ноль кадров, B
        // выбывает из active сам — без сброса pipeline и без единого сэмпла.
        engine.pumpDecoding()
        let staleB = engine.active.contains { ObjectIdentifier($0 as AnyObject) == bID }
        print(
            "FOLLOWUP gapless: nowPlayingStillA=\(engine.nowPlayingID == oldPlaying), staleActiveB=\(staleB), playCalls=\(engine.playCalls)"
        )
        #expect(!staleB, "B ушёл в active до clear, но ещё не nowPlaying; его надо сбросить")
        #expect(engine.nowPlayingID == oldPlaying, "A звучит дальше без перезапуска")
        #expect(engine.playCalls == 1, "кадров B не было — сброс не нужен")
        #expect(engine.queued.count == 1, "следующим заряжен X")
    }

    /// B успел положить кадры в кольцевой буфер до правки очереди: отзыв это
    /// видит, и честен только сброс — текущий трек поднимается заново с той же
    /// секунды, B из pipeline исчезает.
    @Test func activeFutureDecoderWithLeakedFramesForcesAReset() async throws {
        let url = try #require(try fixtures().first)
        let engine = FakeEngine()
        let player = Player(devices: FakeDevices(), engine: engine)
        let a = item(url, id: 1, title: "A")
        let b = item(url, id: 2, title: "B")
        let x = item(url, id: 3, title: "X")
        await player.play(items: [a, b], startAt: 0)
        let preparedB = try #require(engine.queued.first)
        let bID = ObjectIdentifier(preparedB as AnyObject)
        engine.activateArmedOnClear = true
        engine.decodeOnActivate = true
        await player.playNext(items: [x])
        #expect(engine.leakedFrames > 0, "модель: кадры B ушли до отзыва")
        #expect(engine.playCalls == 2, "сброс pipeline")
        #expect(!engine.active.contains { ObjectIdentifier($0 as AnyObject) == bID })
        #expect(await player.currentIndex() == 0)
        #expect(engine.queued.count == 1, "после сброса заряжен X")
    }

    /// Enqueue в конец не меняет следующий трек: заряд остаётся, движок не трогаем.
    @Test func appendingToTheEndKeepsTheArmedTransitionUntouched() async throws {
        let url = try #require(try fixtures().first)
        let engine = FakeEngine()
        let player = Player(devices: FakeDevices(), engine: engine)
        await player.play(
            items: [item(url, id: 1, title: "A"), item(url, id: 2, title: "B")], startAt: 0)
        let armedB = try #require(engine.queued.first)
        let clears = engine.clears
        await player.enqueue(items: [item(url, id: 3, title: "C")])
        #expect(engine.clears == clears)
        #expect(
            engine.queued.first.map { ObjectIdentifier($0 as AnyObject) }
                == ObjectIdentifier(armedB as AnyObject))
    }
}
