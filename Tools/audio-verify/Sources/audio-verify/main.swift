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
    if ProcessInfo.processInfo.environment["VERIFY_DEBUG"] != nil {
        FileHandle.standardError.write(
            Data("debug: format=\(format) length=\(decoder.length)\n".utf8))
    }
    var all: [Float] = []
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65536)!
    while true {
        try decoder.decode(into: buffer, length: 65536)
        if buffer.frameLength == 0 { break }
        let channels = Int(format.channelCount)
        let frames = Int(buffer.frameLength)
        if let data = buffer.floatChannelData {
            // deinterleaved float → interleave as-is
            for frame in 0..<frames {
                for ch in 0..<channels {
                    all.append(data[ch][frame])
                }
            }
        } else if let data = buffer.int32ChannelData {
            // SFB decodes FLAC to high-aligned integer PCM in 4-byte containers.
            // CoreAudio's exact int→float mapping is int32 / 2^31; results fit
            // Float32's 24-bit mantissa losslessly for ≤24-bit sources.
            for frame in 0..<frames {
                for ch in 0..<channels {
                    all.append(Float(Double(data[ch][frame]) / 2_147_483_648.0))
                }
            }
        } else {
            throw VerifyError.playbackFailed("unsupported decode buffer layout: \(format)")
        }
    }
    return (all, format)
}

// MARK: - Loopback capture

/// Пишет вход loopback-устройства напрямую через HAL IOProc — без
/// AVAudioEngine, значит без скрытых конвертаций формата на пути захвата.
/// BlackHole отдаёт на входе ровно те Float32-биты, что пришли на выход.
final class LoopbackRecorder {
    private let deviceID: AudioDeviceID
    private var procID: AudioDeviceIOProcID?
    private let lock = NSLock()
    private var samples: [Float] = []

    init(deviceID: AudioDeviceID) {
        self.deviceID = deviceID
    }

    func start() throws {
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, nil) {
            [weak self] _, inInputData, _, _, _ in
            guard let self else { return }
            let abl = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inInputData))
            var chunk: [[Float]] = []
            for buffer in abl {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let floats = data.bindMemory(to: Float.self, capacity: count)
                chunk.append(Array(UnsafeBufferPointer(start: floats, count: count)))
            }
            guard !chunk.isEmpty else { return }
            let interleaved: [Float]
            if chunk.count == 1 {
                // один буфер: каналы уже интерливлены
                interleaved = chunk[0]
            } else {
                // по буферу на канал: интерливим сами
                let frames = chunk[0].count
                var mixed: [Float] = []
                mixed.reserveCapacity(frames * chunk.count)
                for frame in 0..<frames {
                    for channel in chunk where frame < channel.count {
                        mixed.append(channel[frame])
                    }
                }
                interleaved = mixed
            }
            self.lock.lock()
            self.samples.append(contentsOf: interleaved)
            self.lock.unlock()
        }
        guard status == noErr, let procID else {
            throw VerifyError.captureSetupFailed("AudioDeviceCreateIOProcID: \(status)")
        }
        self.procID = procID
        let startStatus = AudioDeviceStart(deviceID, procID)
        guard startStatus == noErr else {
            throw VerifyError.captureSetupFailed("AudioDeviceStart: \(startStatus)")
        }
    }

    func stop() -> [Float] {
        if let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        procID = nil
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

        // Частоту выставляем ДО старта захвата и воспроизведения; Player увидит
        // совпадение и не будет вставлять паузу смены частоты.
        try await controller.setNominalSampleRate(
            deviceID: loopback.id, rate: Double(meta.rate))
        try await Task.sleep(for: .milliseconds(200))

        let recorder = LoopbackRecorder(deviceID: loopback.id)
        try recorder.start()

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
            _ = recorder.stop()
            return FixtureResult(name: name, passed: false, detail: "playback: \(error)")
        }

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
            var detail = mismatch
            if ProcessInfo.processInfo.environment["VERIFY_DEBUG"] != nil {
                let peakRec = recording.map(abs).max() ?? 0
                let peakRef = reference.prefix(20000).map(abs).max() ?? 0
                let nonzero = recording.lazy.filter { $0 != 0 }.count
                detail +=
                    " [rec: \(recording.count) samples, peak \(peakRec), nonzero \(nonzero); ref peak \(peakRef), ref[0..4]=\(Array(reference.prefix(4))), recNZ[0..4]=\(Array(recording.drop(while: { $0 == 0 }).prefix(4)))]"
            }
            return FixtureResult(name: name, passed: false, detail: detail)
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

// Захват аудио-входа обычно требует microphone-permission (TCC). Статус
// печатаем, но не блокируемся: решает фактический захват — если придут
// одни нули, диагноз в отчёте будет ясен.
let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
print("mic permission status: \(micStatus.rawValue) (3=authorized)")

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
