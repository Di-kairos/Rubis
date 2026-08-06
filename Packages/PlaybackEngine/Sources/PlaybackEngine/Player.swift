import EscapementCore
import Foundation
import SFBAudioEngine

/// A queue entry: the library track plus a resolved playable URL.
/// URL resolution (bookmarks, stream cache) is the app's job — the engine
/// never touches the database or the network.
public struct PlaybackItem: Sendable, Equatable {
    public let track: Track
    public let url: URL

    public init(track: Track, url: URL) {
        self.track = track
        self.url = url
    }
}

/// Playback facade (SPEC §4.2, §4.5): queue, gapless, device preparation,
/// honest OutputStatus. All real-time audio stays inside SFBAudioEngine —
/// nothing here runs on the render thread.
public actor Player {
    public private(set) var state: PlaybackState = .idle {
        didSet { stateContinuations.values.forEach { $0.yield(state) } }
    }
    public private(set) var outputStatus: OutputStatus? {
        didSet { statusContinuations.values.forEach { $0.yield(outputStatus) } }
    }
    /// Set when the output device vanished mid-play (SPEC §9): paused, badge red,
    /// cleared on the next successful play. Never auto-resumes.
    public private(set) var outputDeviceLost = false

    private let engine = AudioPlayer()
    private let devices: AudioDeviceController
    private var config: AudioConfiguration
    private var bridge: DelegateBridge?

    private var queue: [PlaybackItem] = []
    private var index = 0
    private var currentDeviceID: UInt32?
    private var gaplessArmed = false

    private var stateContinuations: [UUID: AsyncStream<PlaybackState>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<OutputStatus?>.Continuation] = [:]

    public init(devices: AudioDeviceController, configuration: AudioConfiguration = .init()) {
        self.devices = devices
        self.config = configuration
    }

    // MARK: - Streams for the UI

    public func stateStream() -> AsyncStream<PlaybackState> {
        let id = UUID()
        return AsyncStream { continuation in
            stateContinuations[id] = continuation
            continuation.yield(state)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeStateContinuation(id) }
            }
        }
    }

    public func statusStream() -> AsyncStream<OutputStatus?> {
        let id = UUID()
        return AsyncStream { continuation in
            statusContinuations[id] = continuation
            continuation.yield(outputStatus)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeStatusContinuation(id) }
            }
        }
    }

    private func removeStateContinuation(_ id: UUID) { stateContinuations[id] = nil }
    private func removeStatusContinuation(_ id: UUID) { statusContinuations[id] = nil }

    // MARK: - Configuration

    public func update(configuration: AudioConfiguration) {
        config = configuration
    }

    // MARK: - Transport

    /// Replaces the queue and starts playback at the given position.
    public func play(items: [PlaybackItem], startAt position: Int = 0) async {
        installBridgeIfNeeded()
        queue = items
        index = min(max(position, 0), max(items.count - 1, 0))
        await startCurrent()
    }

    public func pause() {
        guard case .playing(let track) = state else { return }
        _ = engine.pause()
        state = .paused(track)
    }

    public func resume() {
        guard case .paused(let track) = state, !outputDeviceLost else { return }
        _ = engine.resume()
        state = .playing(track)
    }

    public func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused: resume()
        default: break
        }
    }

    public func stop() {
        engine.stop()
        releaseDevice()
        state = .idle
        outputStatus = nil
    }

    public func next() async {
        guard index + 1 < queue.count else { return }
        index += 1
        await startCurrent()
    }

    public func previous() async {
        guard index > 0 else { return }
        index -= 1
        await startCurrent()
    }

    @discardableResult
    public func seek(to seconds: TimeInterval) -> Bool {
        engine.seek(time: seconds)
    }

    public func playbackTime() -> (current: TimeInterval, total: TimeInterval)? {
        guard let time = engine.time,
            let current = time.current,
            let total = time.total
        else { return nil }
        return (current, total)
    }

    // MARK: - Hardware volume passthrough (SPEC §4.4)

    public func deviceHasVolumeControl() async -> Bool {
        guard let id = currentDeviceID else { return false }
        return await devices.hasVolumeControl(deviceID: id)
    }

    public func deviceVolume() async -> Float? {
        guard let id = currentDeviceID else { return nil }
        return await devices.volumeScalar(deviceID: id)
    }

    public func setDeviceVolume(_ value: Float) async {
        guard let id = currentDeviceID else { return }
        try? await devices.setVolumeScalar(deviceID: id, value: value)
    }

    // MARK: - Engine internals

    private func startCurrent() async {
        guard queue.indices.contains(index) else {
            stop()
            return
        }
        let item = queue[index]
        state = .loading(item.track)
        outputDeviceLost = false
        do {
            try await prepareDevice(for: item.track)
            try engine.play(item.url)
            state = .playing(item.track)
            armGapless()
        } catch let error as PlaybackError {
            state = .failed(item.track, error)
        } catch {
            state = .failed(item.track, .decodingFailed(error.localizedDescription))
        }
    }

    /// Device preparation per SPEC §4.2: resolve device, hog, kill mixer,
    /// match sample rate, compute honest OutputStatus.
    private func prepareDevice(for track: Track) async throws {
        let info: AudioDeviceController.DeviceInfo?
        if let uid = config.preferredDeviceUID {
            info = try await devices.device(uid: uid)
        } else {
            info = try await devices.defaultOutputDevice()
        }
        guard let device = info else { throw PlaybackError.deviceUnavailable }

        if currentDeviceID != device.id {
            releaseDevice()
            try engine.setOutputDeviceID(device.id)
            currentDeviceID = device.id
            try? await devices.observeDeviceDeath(deviceID: device.id) { [weak self] in
                Task { await self?.handleDeviceLoss() }
            }
        }

        var exclusive = false
        if config.exclusiveAccess {
            exclusive = await devices.startHogging(deviceID: device.id)
            if exclusive {
                await devices.disableMixing(deviceID: device.id)
            }
        }

        let available = try await devices.availableSampleRates(deviceID: device.id)
        let source = Double(track.sampleRate)
        let decision = SampleRatePolicy.choose(
            source: source, available: available, fallback: config.rateFallback)

        let targetRate: Double
        var exactRate = false
        switch decision {
        case .exact(let rate):
            targetRate = rate
            exactRate = true
        case .familyMultiple(let rate), .crossFamily(let rate):
            targetRate = rate
        case .refuse:
            throw PlaybackError.deviceUnavailable
        }

        let currentRate = try await devices.nominalSampleRate(deviceID: device.id)
        if currentRate != targetRate {
            try await devices.setNominalSampleRate(deviceID: device.id, rate: targetRate)
            // Silence gap only when the rate really changed (SPEC §4.2.4).
            try await Task.sleep(for: config.sampleRateChangeDelay)
        }

        outputStatus = OutputStatus(
            deviceName: device.name,
            deviceSampleRate: targetRate,
            sourceSampleRate: source,
            sourceBitDepth: track.bitDepth ?? 16,
            isExclusive: exclusive,
            isBitPerfect: exclusive && exactRate,
            dsdMode: track.codec == "dsf" || track.codec == "dff" ? config.dsdMode : nil)
    }

    /// Preloads the next queue item for gapless transition when the sample
    /// rate matches (SPEC §4.2.5) — SFBAudioEngine handles the seam.
    private func armGapless() {
        gaplessArmed = false
        let nextIndex = index + 1
        guard queue.indices.contains(nextIndex) else { return }
        let current = queue[index]
        let next = queue[nextIndex]
        guard next.track.sampleRate == current.track.sampleRate else { return }
        if (try? engine.enqueue(next.url)) != nil {
            gaplessArmed = true
        }
    }

    private func handleDeviceLoss() {
        guard case .playing(let track) = state else { return }
        _ = engine.pause()
        outputDeviceLost = true
        currentDeviceID = nil
        state = .paused(track)
        outputStatus = nil
        Log.audio.error("output device lost — playback paused")
    }

    private func releaseDevice() {
        if let id = currentDeviceID {
            Task { [devices] in
                await devices.stopObservingDeviceDeath()
                await devices.stopHogging(deviceID: id)
            }
        }
    }

    // MARK: - Delegate events

    private enum EngineEvent: Sendable {
        case nowPlayingChanged
        case endOfAudio
        case error(String)
    }

    private func installBridgeIfNeeded() {
        guard bridge == nil else { return }
        let bridge = DelegateBridge { [weak self] event in
            Task { await self?.handle(event) }
        }
        engine.delegate = bridge
        self.bridge = bridge
    }

    private func handle(_ event: EngineEvent) async {
        switch event {
        case .nowPlayingChanged:
            // The engine moved to a gapless-enqueued decoder: advance bookkeeping.
            if gaplessArmed, case .playing = state, queue.indices.contains(index + 1) {
                index += 1
                state = .playing(queue[index].track)
                armGapless()
            }
        case .endOfAudio:
            if queue.indices.contains(index + 1) {
                index += 1
                await startCurrent()
            } else {
                stop()
            }
        case .error(let message):
            if queue.indices.contains(index) {
                state = .failed(queue[index].track, .decodingFailed(message))
            }
        }
    }

    private final class DelegateBridge: NSObject, AudioPlayer.Delegate {
        private let onEvent: @Sendable (EngineEvent) -> Void

        init(onEvent: @escaping @Sendable (EngineEvent) -> Void) {
            self.onEvent = onEvent
        }

        func audioPlayer(
            _ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: (any PCMDecoding)?
        ) {
            if nowPlaying != nil {
                onEvent(.nowPlayingChanged)
            }
        }

        func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
            onEvent(.endOfAudio)
        }

        func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: any Error) {
            onEvent(.error(error.localizedDescription))
        }
    }
}
