// audio-verify — CLI подтверждения bit-perfect тракта (SPEC §4.6).
//
// Схема: каждый файл из Fixtures/ проигрывается через PlaybackEngine в
// loopback-устройство (BlackHole 2ch), одновременно вход BlackHole пишется
// в память, затем запись побитово сравнивается с эталонной декодировкой файла.
// Acceptance фазы 3 — совпадение для 44.1–192 кГц, 16 и 24 бит.

import AVFoundation
import CoreAudio
import EscapementCore
import Foundation
import PlaybackEngine
import SFBAudioEngine

// MARK: - Reference decode

/// Декодирует файл целиком в интерливленный Float32 (точное представление
/// для источников ≤ 24 бит — сравнение по битам корректно).
func decodeReference(url: URL) throws -> (samples: [Float], format: AVAudioFormat) {
    let decoder = try AudioDecoder(url: url)
    try decoder.open()
    let format = decoder.processingFormat
    var all: [Float] = []
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65536)!
    while true {
        try decoder.decode(into: buffer, length: 65536)
        if buffer.frameLength == 0 { break }
        let channels = Int(format.channelCount)
        let frames = Int(buffer.frameLength)
        if let data = buffer.floatChannelData {
            // deinterleaved → interleave
            for frame in 0..<frames {
                for ch in 0..<channels {
                    all.append(data[ch][frame])
                }
            }
        }
    }
    return (all, format)
}

// MARK: - Loopback capture

/// Пишет вход указанного устройства (BlackHole) в память через AVAudioEngine.
final class LoopbackRecorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []

    init(deviceID: AudioDeviceID) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw VerifyError.captureSetupFailed("no input audio unit")
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            audioUnit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw VerifyError.captureSetupFailed("cannot bind input to loopback device")
        }
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData else { return }
            let channels = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            var chunk: [Float] = []
            chunk.reserveCapacity(frames * channels)
            for frame in 0..<frames {
                for ch in 0..<channels {
                    chunk.append(data[ch][frame])
                }
            }
            self.lock.lock()
            self.samples.append(contentsOf: chunk)
            self.lock.unlock()
        }
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

// MARK: - Comparison

/// Ищет референс в записи (запись начинается с тишины/мусора) и сравнивает
/// побитово весь остаток. Возвращает nil при успехе, иначе описание ошибки.
func compare(reference: [Float], recording: [Float], channels: Int) -> String? {
    guard !reference.isEmpty else { return "empty reference" }
    guard recording.count >= reference.count else {
        return "recording shorter than reference (\(recording.count) < \(reference.count))"
    }
    // Окно поиска — первые 2048 сэмплов референса, пропуская нулевой хвост.
    let window = min(2048, reference.count)
    var offset: Int?
    let searchLimit = recording.count - reference.count
    outer: for candidate in 0...max(searchLimit, 0) {
        if recording[candidate] == reference[0] {
            for i in 1..<window where recording[candidate + i] != reference[i] {
                continue outer
            }
            offset = candidate
            break
        }
    }
    guard let start = offset else { return "reference pattern not found in recording" }

    // Хвост записи может обрезаться на не-кратной границе буфера — допускаем
    // недостающие последние < 1 буфер (4096×ch) сэмплов.
    let tailSlack = 4096 * channels
    let comparable = min(reference.count, recording.count - start)
    guard reference.count - comparable <= tailSlack else {
        return "recording truncated: only \(comparable)/\(reference.count) samples captured"
    }
    for i in 0..<comparable where recording[start + i] != reference[i] {
        return
            "first mismatch at sample \(i) (offset \(start)): ref \(reference[i]) rec \(recording[start + i])"
    }
    return nil
}

// MARK: - Device discovery

enum VerifyError: Error, CustomStringConvertible {
    case loopbackNotFound
    case captureSetupFailed(String)
    case playbackFailed(String)

    var description: String {
        switch self {
        case .loopbackNotFound:
            return """
                Loopback device not found. Install BlackHole 2ch:
                  brew install blackhole-2ch
                (перезагрузка coreaudiod: sudo killall coreaudiod)
                """
        case .captureSetupFailed(let reason): return "capture setup failed: \(reason)"
        case .playbackFailed(let reason): return "playback failed: \(reason)"
        }
    }
}

func findLoopbackDevice(_ controller: AudioDeviceController) async throws
    -> AudioDeviceController.DeviceInfo
{
    let devices = try await controller.outputDevices()
    guard
        let loopback = devices.first(where: {
            $0.name.localizedCaseInsensitiveContains("BlackHole")
        })
    else { throw VerifyError.loopbackNotFound }
    return loopback
}

// MARK: - Single-file verification

struct FixtureResult {
    let name: String
    let passed: Bool
    let detail: String
}

func parseFixture(url: URL) -> (rate: Int, bits: Int)? {
    // имя вида sine-176400-24.flac
    let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
    guard parts.count == 3, let rate = Int(parts[1]), let bits = Int(parts[2]) else { return nil }
    return (rate, bits)
}

func verifyFixture(
    url: URL, loopback: AudioDeviceController.DeviceInfo,
    controller: AudioDeviceController
) async -> FixtureResult {
    let name = url.lastPathComponent
    guard let meta = parseFixture(url: url) else {
        return FixtureResult(name: name, passed: false, detail: "unparseable fixture name")
    }
    do {
        let (reference, refFormat) = try decodeReference(url: url)
        let channels = Int(refFormat.channelCount)

        // Частоту устройству выставит Player; рекордер стартует после этого,
        // чтобы input format уже соответствовал целевой частоте.
        let player = Player(
            devices: controller,
            configuration: AudioConfiguration(
                exclusiveAccess: false,  // BlackHole делит вход и выход — hog ломает захват
                sampleRateChangeDelay: .milliseconds(150),
                rateFallback: .refuse,
                preferredDeviceUID: loopback.uid))

        let track = Track(
            sourceId: "audio-verify", title: name, duration: 5,
            codec: "flac", sampleRate: meta.rate, bitDepth: meta.bits)

        await player.play(items: [PlaybackItem(track: track, url: url)])

        if case .failed(_, let error) = await player.state {
            return FixtureResult(name: name, passed: false, detail: "playback: \(error)")
        }

        let recorder = try LoopbackRecorder(deviceID: loopback.id)
        try recorder.start()

        // Ждём конца воспроизведения (фикстура 5 с + запас).
        var waited = 0
        while waited < 8000 {
            if case .idle = await player.state { break }
            try await Task.sleep(for: .milliseconds(100))
            waited += 100
        }
        try await Task.sleep(for: .milliseconds(300))
        let recording = recorder.stop()
        await player.stop()

        if let mismatch = compare(reference: reference, recording: recording, channels: channels) {
            return FixtureResult(name: name, passed: false, detail: mismatch)
        }
        return FixtureResult(name: name, passed: true, detail: "bit-perfect")
    } catch {
        return FixtureResult(name: name, passed: false, detail: "\(error)")
    }
}

// MARK: - Entry point

let fixturesDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Fixtures")

guard
    let fixtureURLs = try? FileManager.default.contentsOfDirectory(
        at: fixturesDir, includingPropertiesForKeys: nil
    )
    .filter({ $0.pathExtension == "flac" })
    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }),
    !fixtureURLs.isEmpty
else {
    print("No fixtures in \(fixturesDir.path). Run Tools/make-fixtures.sh first.")
    exit(2)
}

let controller = AudioDeviceController()
let loopback: AudioDeviceController.DeviceInfo
do {
    loopback = try await findLoopbackDevice(controller)
} catch {
    print("\(error)")
    exit(2)
}

print("Loopback: \(loopback.name) [\(loopback.uid)]")
print("Fixtures: \(fixtureURLs.count)\n")

var results: [FixtureResult] = []
for url in fixtureURLs {
    let result = await verifyFixture(url: url, loopback: loopback, controller: controller)
    let mark = result.passed ? "PASS" : "FAIL"
    print("[\(mark)] \(result.name) — \(result.detail)")
    results.append(result)
}

let failed = results.filter { !$0.passed }
print("\n\(results.count - failed.count)/\(results.count) bit-perfect")
exit(failed.isEmpty ? 0 : 1)
