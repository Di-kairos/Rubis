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

    /// Порядок, в котором очередь пришла — база для выключения shuffle.
    private var sourceQueue: [PlaybackItem] = []
    /// Фактический порядок воспроизведения.
    private var queue: [PlaybackItem] = []
    private var index = 0
    public private(set) var repeatMode: RepeatMode = .off
    public private(set) var shuffleMode: ShuffleMode = .off
    private var random = SystemRandomNumberGenerator()
    private var currentDeviceID: UInt32?
    private var gaplessArmed = false
    /// Set by prepareDevice when the current track goes out as DoP packets.
    private var currentUsesDoP = false

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
        sourceQueue = items
        let start = min(max(position, 0), max(items.count - 1, 0))
        if shuffleMode == .off {
            queue = items
            index = start
        } else {
            queue = PlaybackOrder.shuffled(
                items: items, current: items.indices.contains(start) ? items[start] : nil,
                mode: shuffleMode, using: &random)
            index = 0
        }
        await startCurrent()
    }

    /// Треки сразу после текущего — не трогая остальную очередь.
    public func playNext(items: [PlaybackItem]) {
        guard !items.isEmpty else { return }
        let insertion = queue.isEmpty ? 0 : index + 1
        queue.insert(contentsOf: items, at: insertion)
        sourceQueue.append(contentsOf: items)
        armGapless()
    }

    /// Треки в конец очереди.
    public func enqueue(items: [PlaybackItem]) {
        guard !items.isEmpty else { return }
        queue.append(contentsOf: items)
        sourceQueue.append(contentsOf: items)
        armGapless()
    }

    public func queuedItems() -> [PlaybackItem] { queue }

    // MARK: - Порядок обхода (SPEC §7.3 транспорт)

    public func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
    }

    /// Меняет режим и перестраивает остаток очереди, не трогая текущий трек.
    public func setShuffleMode(_ mode: ShuffleMode) {
        shuffleMode = mode
        let current = queue.indices.contains(index) ? queue[index] : nil
        if mode == .off {
            queue = sourceQueue
            index =
                current.flatMap { item in
                    queue.firstIndex { $0.track.id == item.track.id }
                } ?? 0
        } else {
            queue = PlaybackOrder.shuffled(
                items: sourceQueue, current: current, mode: mode, using: &random)
            index = 0
        }
        armGapless()
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
        guard
            let position = PlaybackOrder.manualNext(
                after: index, count: queue.count, repeatMode: repeatMode)
        else { return }
        index = position
        await startCurrent()
    }

    public func previous() async {
        guard
            let position = PlaybackOrder.previous(
                before: index, count: queue.count, repeatMode: repeatMode)
        else { return }
        index = position
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
            try engine.play(makeDecoder(for: item))
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
        // Hog only external/virtual devices. Hogging the built-in output makes
        // CoreAudio republish the device mid-flight; AVAudioEngine's config-change
        // notification then sees an invalid output format and SFB's noexcept
        // handler dies on NSException (IsFormatSampleRateAndChannelCountValid)
        // → SIGABRT. Bit-perfect through built-in speakers is fiction anyway —
        // the badge honestly shows Shared.
        if config.exclusiveAccess, await !devices.isBuiltInDevice(deviceID: device.id) {
            exclusive = await devices.startHogging(deviceID: device.id)
            if exclusive {
                await devices.disableMixing(deviceID: device.id)
            }
        }

        let available = try await devices.availableSampleRates(deviceID: device.id)
        let plan = try ratePlan(for: track, available: available)
        currentUsesDoP = plan.usesDoP

        let currentRate = try await devices.nominalSampleRate(deviceID: device.id)
        if currentRate != plan.target {
            try await devices.setNominalSampleRate(deviceID: device.id, rate: plan.target)
            // Silence gap only when the rate really changed (SPEC §4.2.4).
            try await Task.sleep(for: config.sampleRateChangeDelay)
        }

        outputStatus = OutputStatus(
            deviceName: device.name,
            deviceSampleRate: plan.target,
            sourceSampleRate: Double(track.sampleRate),
            sourceBitDepth: track.bitDepth ?? 16,
            isExclusive: exclusive,
            isBitPerfect: exclusive && plan.exact,
            dsdMode: plan.isDSD ? config.dsdMode : nil)
    }

    private struct RatePlan {
        let target: Double
        /// Signal leaves the app unmodified (exact PCM rate or DoP passthrough).
        let exact: Bool
        let isDSD: Bool
        let usesDoP: Bool
    }

    /// Device rate plan for a track (SPEC §4.2.3 PCM, §4.2.6 DSD).
    private func ratePlan(for track: Track, available: [Double]) throws -> RatePlan {
        let isDSD = track.codec == "dsf" || track.codec == "dff"
        if isDSD {
            // DoP carries DSD in PCM frames at dsdRate/16 (DSD64 → 176.4k).
            let dopRate = Double(track.sampleRate) / 16.0
            if config.dsdMode == .dopIfAvailable, available.contains(dopRate) {
                return RatePlan(target: dopRate, exact: true, isDSD: true, usesDoP: true)
            }
            // Conversion path: DSD → PCM 24/176.4 (SPEC §4.2.6), never bit-perfect.
            switch SampleRatePolicy.choose(
                source: 176400, available: available, fallback: config.rateFallback)
            {
            case .exact(let rate), .familyMultiple(let rate), .crossFamily(let rate):
                return RatePlan(target: rate, exact: false, isDSD: true, usesDoP: false)
            case .refuse:
                throw PlaybackError.deviceUnavailable
            }
        }
        switch SampleRatePolicy.choose(
            source: Double(track.sampleRate), available: available, fallback: config.rateFallback)
        {
        case .exact(let rate):
            return RatePlan(target: rate, exact: true, isDSD: false, usesDoP: false)
        case .familyMultiple(let rate), .crossFamily(let rate):
            return RatePlan(target: rate, exact: false, isDSD: false, usesDoP: false)
        case .refuse:
            throw PlaybackError.deviceUnavailable
        }
    }

    /// Builds the decoder chain: plain PCM, DoP passthrough, or DSD→PCM.
    private func makeDecoder(for item: PlaybackItem) throws -> any PCMDecoding {
        let isDSD = item.track.codec == "dsf" || item.track.codec == "dff"
        guard isDSD else {
            return try AudioDecoder(url: item.url)
        }
        let dsd = try DSDDecoder(url: item.url)
        return currentUsesDoP
            ? try DoPDecoder(decoder: dsd) as any PCMDecoding
            : try DSDPCMDecoder(decoder: dsd) as any PCMDecoding
    }

    /// Preloads the next queue item for gapless transition when the sample
    /// rate matches (SPEC §4.2.5) — SFBAudioEngine handles the seam.
    private func armGapless() {
        gaplessArmed = false
        guard
            let nextIndex = PlaybackOrder.next(
                after: index, count: queue.count, repeatMode: repeatMode),
            nextIndex != index,  // repeat track: перезапуск не склеиваем
            queue.indices.contains(nextIndex)
        else { return }
        let current = queue[index]
        let next = queue[nextIndex]
        // Gapless only within one PCM format family; DSD transitions restart cleanly.
        guard next.track.sampleRate == current.track.sampleRate,
            next.track.codec != "dsf", next.track.codec != "dff",
            current.track.codec != "dsf", current.track.codec != "dff",
            let decoder = try? makeDecoder(for: next)
        else { return }
        if (try? engine.enqueue(decoder)) != nil {
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
            if gaplessArmed, case .playing = state,
                let position = PlaybackOrder.next(
                    after: index, count: queue.count, repeatMode: repeatMode),
                queue.indices.contains(position)
            {
                index = position
                state = .playing(queue[index].track)
                armGapless()
            }
        case .endOfAudio:
            if let position = PlaybackOrder.next(
                after: index, count: queue.count, repeatMode: repeatMode),
                queue.indices.contains(position)
            {
                index = position
                await startCurrent()
            } else {
                // endOfAudio fires when the last frame is rendered into the
                // engine, not when the device drains its buffer (~100 ms).
                // Immediate stop() would clip the audible tail of the last track.
                try? await Task.sleep(for: .milliseconds(250))
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
