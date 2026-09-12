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
    /// Секунда, на которой пропал выход — с неё Play поднимает трек заново.
    private var lostAtOffset: TimeInterval?

    private let engine = AudioPlayer()
    private let devices: AudioDeviceController
    private var config: AudioConfiguration
    private var bridge: DelegateBridge?
    /// События движка идут одним потоком в порядке прихода: `renderingComplete`
    /// и `endOfAudio` рождаются в одном замыкании render-треда, и отдельная
    /// `Task` на каждое событие могла бы поменять их местами.
    private var eventPump: Task<Void, Never>?

    /// Порядок, в котором очередь пришла — база для выключения shuffle.
    private var sourceQueue: [PlaybackItem] = []
    /// Фактический порядок воспроизведения.
    private var queue: [PlaybackItem] = []
    /// Позиция в `sourceQueue` для каждой позиции `queue`: shuffle различает
    /// вхождения, а не треки — `[A, B, A]` остаётся тремя элементами, и
    /// выключение shuffle возвращает именно то вхождение, что играло.
    private var sourceIndices: [Int] = []
    private var index = 0
    public private(set) var repeatMode: RepeatMode = .off
    public private(set) var shuffleMode: ShuffleMode = .off
    private var random = SystemRandomNumberGenerator()
    private var currentDeviceID: UInt32?
    /// Устройство, у которого держим hog, — чтобы отпустить ровно его, в том
    /// числе когда exclusive выключили, не меняя выход.
    private var hoggedDeviceID: UInt32?

    /// Поколение транспортной команды: растёт на каждом старте и стопе.
    /// Команда, пережившая `await`, сверяет своё поколение и молча выходит,
    /// если её обогнала следующая — иначе медленный старт A доигрывал бы
    /// поверх уже выбранного B, а задержанный stop гасил бы новый трек.
    private var generation: UInt64 = 0
    /// Декодер, который играет сейчас.
    private var currentDecoderID: ObjectIdentifier?
    /// Декодер, заряженный на gapless, и поколение, при котором его ставили.
    /// `nowPlayingChanged` двигает индекс только для него: событие от ручного
    /// старта не должно двигать очередь — иначе клик по треку «играет
    /// следующий».
    private var armed: (decoder: ObjectIdentifier, generation: UInt64)?
    /// Последний декодер, который движок дорендерил до конца. `endOfAudio`
    /// не несёт идентичности, поэтому признаётся только вслед за концом
    /// текущего декодера — опоздавшее событие прежнего трека не двигает
    /// очередь.
    private var renderedOut: ObjectIdentifier?
    /// Set by prepareDevice when the current track goes out as DoP packets.
    private var currentUsesDoP = false
    /// Позиция из прошлого запуска: применяется к первому же старту и гасится.
    private var pendingSeek: TimeInterval?

    private var stateContinuations: [UUID: AsyncStream<PlaybackState>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<OutputStatus?>.Continuation] = [:]

    /// Команда устарела: пока она ждала устройство, пришла следующая.
    private struct Superseded: Error {}

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
        // Пользователь сам выбрал, что играть — позиция из прошлого запуска
        // больше не относится ни к чему.
        pendingSeek = nil
        let start = min(max(position, 0), max(items.count - 1, 0))
        applyOrder(currentSourceIndex: items.isEmpty ? nil : start)
        await startCurrent()
    }

    /// Восстановление очереди при запуске: состав и позиция без старта звука.
    /// `offset` — секунды внутри трека, с которых продолжить: первый Play
    /// стартует трек и сразу перематывает туда.
    public func restore(items: [PlaybackItem], at position: Int, offset: TimeInterval = 0) {
        installBridgeIfNeeded()
        sourceQueue = items
        queue = items
        sourceIndices = Array(items.indices)
        index = min(max(position, 0), max(items.count - 1, 0))
        pendingSeek = offset > 0 ? offset : nil
    }

    /// Старт текущего элемента восстановленной очереди (Play из idle).
    /// Единственный путь, который применяет позицию из прошлого запуска.
    public func playCurrent() async {
        guard !queue.isEmpty else { return }
        let offset = pendingSeek
        pendingSeek = nil
        await startCurrent(seekTo: offset)
    }

    public func currentIndex() -> Int { index }

    /// Повторная попытка склеить с следующим треком. Нужна серверным трекам
    /// (SPEC §6.2): в момент старта текущего файл следующего ещё качается,
    /// поэтому склейка не собирается — приложение зовёт это, когда файл лёг.
    public func rearmGapless() async {
        guard case .playing = state else { return }
        await armGapless()
    }

    /// Треки сразу после текущего — не трогая остальную очередь.
    public func playNext(items: [PlaybackItem]) async {
        guard !items.isEmpty else { return }
        let insertion = queue.isEmpty ? 0 : index + 1
        let firstSource = sourceQueue.count
        queue.insert(contentsOf: items, at: insertion)
        sourceQueue.append(contentsOf: items)
        sourceIndices.insert(
            contentsOf: firstSource..<(firstSource + items.count), at: insertion)
        await armGapless()
    }

    /// Треки в конец очереди.
    public func enqueue(items: [PlaybackItem]) async {
        guard !items.isEmpty else { return }
        let firstSource = sourceQueue.count
        queue.append(contentsOf: items)
        sourceQueue.append(contentsOf: items)
        sourceIndices.append(contentsOf: firstSource..<(firstSource + items.count))
        await armGapless()
    }

    public func queuedItems() -> [PlaybackItem] { queue }

    // MARK: - Порядок обхода (SPEC §7.3 транспорт)

    public func setRepeatMode(_ mode: RepeatMode) async {
        repeatMode = mode
        // Repeat меняет, что идёт после текущего трека; заряженный переход
        // должен это отражать, а не звучать по прежнему плану.
        if case .playing = state { await armGapless() }
    }

    /// Меняет режим и перестраивает остаток очереди, не трогая текущий трек.
    public func setShuffleMode(_ mode: ShuffleMode) async {
        shuffleMode = mode
        let currentSource = sourceIndices.indices.contains(index) ? sourceIndices[index] : nil
        applyOrder(currentSourceIndex: currentSource)
        await armGapless()
    }

    /// Раскладывает `sourceQueue` в `queue` по текущему режиму. Текущее
    /// вхождение (позиция в `sourceQueue`) остаётся тем, что играет.
    private func applyOrder(currentSourceIndex: Int?) {
        if shuffleMode == .off {
            queue = sourceQueue
            sourceIndices = Array(sourceQueue.indices)
            index = currentSourceIndex ?? 0
        } else {
            sourceIndices = PlaybackOrder.shuffledIndices(
                items: sourceQueue, currentIndex: currentSourceIndex, mode: shuffleMode,
                using: &random)
            queue = sourceIndices.map { sourceQueue[$0] }
            index = 0
        }
    }

    public func pause() {
        guard case .playing(let track) = state else { return }
        _ = engine.pause()
        state = .paused(track)
    }

    public func resume() async {
        guard case .paused(let track) = state else { return }
        switch ResumePolicy.decide(deviceLost: outputDeviceLost, offset: lostAtOffset) {
        case .continueEngine:
            _ = engine.resume()
            state = .playing(track)
        case .restart(let offset):
            await startCurrent(seekTo: offset)
        }
    }

    public func togglePlayPause() async {
        switch state {
        case .playing: pause()
        case .paused: await resume()
        case .idle: await playCurrent()  // восстановленная очередь: Play её будит
        default: break
        }
    }

    public func stop() async {
        generation &+= 1
        armed = nil
        engine.stop()
        await releaseDevice()
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

    /// `seekTo` заполняет только `playCurrent()` — продолжение с места остановки.
    /// Любой другой старт (клик по треку, next, previous) играет с начала.
    private func startCurrent(seekTo offset: TimeInterval? = nil) async {
        generation &+= 1
        let mine = generation
        armed = nil
        guard queue.indices.contains(index) else {
            await stop()
            return
        }
        let item = queue[index]
        state = .loading(item.track)
        outputDeviceLost = false
        lostAtOffset = nil
        do {
            try await prepareDevice(for: item.track, generation: mine)
            let decoder = try makeDecoder(for: item)
            currentDecoderID = ObjectIdentifier(decoder as AnyObject)
            try engine.play(decoder)
            if let offset { _ = engine.seek(time: offset) }
            state = .playing(item.track)
            await armGapless()
        } catch is Superseded {
            // Следующая команда уже ведёт транспорт — ей и состояние.
            return
        } catch let error as PlaybackError {
            await fail(item.track, with: error, generation: mine)
        } catch {
            await fail(
                item.track, with: .decodingFailed(error.localizedDescription), generation: mine)
        }
    }

    /// Ошибка старта не оставляет за собой ни звука, ни hog: прежний трек мог
    /// ещё играть, устройство — оставаться захваченным.
    private func fail(_ track: Track, with error: PlaybackError, generation mine: UInt64)
        async
    {
        guard mine == generation else { return }
        engine.stop()
        await releaseDevice()
        guard mine == generation else { return }
        state = .failed(track, error)
        outputStatus = nil
    }

    /// Device preparation per SPEC §4.2: resolve device, hog, kill mixer,
    /// match sample rate, compute honest OutputStatus. Каждое ожидание
    /// сверяет поколение: за это время очередь могла смениться.
    private func prepareDevice(for track: Track, generation mine: UInt64) async throws {
        let info: AudioDeviceController.DeviceInfo?
        if let uid = config.preferredDeviceUID {
            info = try await devices.device(uid: uid)
        } else {
            info = try await devices.defaultOutputDevice()
        }
        try checkCurrent(mine)
        guard let device = info else { throw PlaybackError.deviceUnavailable }

        if currentDeviceID != device.id {
            await releaseDevice()
            try checkCurrent(mine)
            try engine.setOutputDeviceID(device.id)
            currentDeviceID = device.id
            try? await devices.observeDeviceDeath(deviceID: device.id) { [weak self] in
                Task { await self?.handleDeviceLoss() }
            }
            try checkCurrent(mine)
        }

        var exclusive = false
        // Hog only external/virtual devices. Hogging the built-in output makes
        // CoreAudio republish the device mid-flight; AVAudioEngine's config-change
        // notification then sees an invalid output format and SFB's noexcept
        // handler dies on NSException (IsFormatSampleRateAndChannelCountValid)
        // → SIGABRT. Bit-perfect through built-in speakers is fiction anyway —
        // the badge honestly shows Shared.
        if config.exclusiveAccess, await !devices.isBuiltInDevice(deviceID: device.id) {
            if hoggedDeviceID == device.id {
                exclusive = true
            } else {
                exclusive = await devices.startHogging(deviceID: device.id)
            }
            hoggedDeviceID = exclusive ? device.id : nil
            if exclusive {
                _ = await devices.disableMixing(deviceID: device.id)
            }
        } else if let hogged = hoggedDeviceID {
            // Exclusive выключили, выход тот же: hog отпускается, а не висит до
            // смены устройства.
            await devices.stopHogging(deviceID: hogged)
            hoggedDeviceID = nil
        }
        try checkCurrent(mine)

        let available = try await devices.availableSampleRates(deviceID: device.id)
        let plan = try ratePlan(for: track, available: available, deviceName: device.name)
        currentUsesDoP = plan.usesDoP

        let currentRate = try await devices.nominalSampleRate(deviceID: device.id)
        try checkCurrent(mine)
        if currentRate != plan.target {
            try await devices.setNominalSampleRate(deviceID: device.id, rate: plan.target)
            // Silence gap only when the rate really changed (SPEC §4.2.4).
            try await Task.sleep(for: config.sampleRateChangeDelay)
            try checkCurrent(mine)
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

    private func checkCurrent(_ mine: UInt64) throws {
        if mine != generation { throw Superseded() }
    }

    private struct RatePlan {
        let target: Double
        /// Signal leaves the app unmodified (exact PCM rate or DoP passthrough).
        let exact: Bool
        let isDSD: Bool
        let usesDoP: Bool
    }

    /// Device rate plan for a track (SPEC §4.2.3 PCM, §4.2.6 DSD).
    private func ratePlan(for track: Track, available: [Double], deviceName: String) throws
        -> RatePlan
    {
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
                throw PlaybackError.rateRefused(source: 176_400, device: deviceName)
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
            throw PlaybackError.rateRefused(
                source: Double(track.sampleRate), device: deviceName)
        }
    }

    /// Builds the decoder chain: plain PCM, DoP passthrough, or DSD→PCM.
    private func makeDecoder(for item: PlaybackItem) throws -> any PCMDecoding {
        let isDSD = item.track.codec == "dsf" || item.track.codec == "dff"
        // Дорожка внутри общего файла (рип с CUE, D-013). Регион считает
        // SFBAudioEngine — декодер сам сообщает конец на границе сегмента,
        // поэтому и очередь, и склейка gapless работают как с обычным файлом.
        // ponytail: DSD-рип с CUE играет файлом целиком — DSDDecoder региона
        // не умеет, а DSD раздают образом SACD, а не диском с листом.
        if !isDSD, let region = CueRegion(track: item.track) {
            return try region.decoder(url: item.url)
        }
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
    ///
    /// Идемпотентно относительно прежнего заряда. `enqueue` движка только
    /// добавляет декодер в очередь, поэтому каждый вызов сперва убирает
    /// прежний. Но очередь движка — не весь путь: decoding thread забирает
    /// декодер в active, как только текущий *додекодирован*, задолго до того,
    /// как он дозвучал. Прежний заряд, уже ушедший в active, `clearQueue` не
    /// достаёт — такой B зазвучал бы после X при UI, который его не ждёт.
    /// Отсюда три ветки: B уже слышен → это состоявшийся переход; B ушёл в
    /// active, но не слышен → текущий трек перезапускается с той же секунды,
    /// что сбрасывает весь pipeline движка (короткая пауза принята явно, тихо
    /// сыграть удалённый B нельзя); B ещё в очереди → просто очистка.
    /// ponytail: окно «B ушёл в active между проверкой и очисткой» остаётся —
    /// закрывать выборочной отменой, если движок её опубликует.
    private func armGapless() async {
        if let previous = armed {
            armed = nil
            if let now = engine.nowPlaying,
                ObjectIdentifier(now as AnyObject) == previous.decoder
            {
                advance(to: previous.decoder)
            } else if engine.queueIsEmpty {
                await startCurrent(seekTo: engine.time?.current)
                return
            }
        }
        engine.clearQueue()
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
            armed = (ObjectIdentifier(decoder as AnyObject), generation)
        }
    }

    /// Заряженный переход состоялся: очередь двигается на следующий элемент.
    private func advance(to decoderID: ObjectIdentifier) {
        guard
            let position = PlaybackOrder.next(
                after: index, count: queue.count, repeatMode: repeatMode),
            queue.indices.contains(position)
        else { return }
        index = position
        currentDecoderID = decoderID
        armed = nil
        state = .playing(queue[index].track)
    }

    private func handleDeviceLoss() async {
        switch state {
        case .playing(let track):
            // Позиция снимается ДО паузы: у мёртвого устройства время читается,
            // пока движок ещё держит текущий декодер.
            lostAtOffset = engine.time?.current
            _ = engine.pause()
            state = .paused(track)
        case .paused:
            // Выход выдернули на паузе: Play обязан поднять трек заново на
            // новом устройстве, а не продолжать движок в никуда.
            lostAtOffset = engine.time?.current
        default:
            return
        }
        outputDeviceLost = true
        await devices.stopObservingDeviceDeath()
        currentDeviceID = nil
        hoggedDeviceID = nil
        outputStatus = nil
        Log.audio.error("output device lost — playback paused")
    }

    /// Отпускает выход целиком и ждёт этого: наблюдение снято, hog отдан,
    /// идентичность сброшена — следующий старт заново установит и то, и
    /// другое. Отложенная очистка в отдельной задаче пересекалась с новой
    /// настройкой, а не сброшенный `currentDeviceID` оставлял Stop→Play без
    /// наблюдения за пропажей устройства.
    private func releaseDevice() async {
        await devices.stopObservingDeviceDeath()
        if let hogged = hoggedDeviceID {
            await devices.stopHogging(deviceID: hogged)
        }
        hoggedDeviceID = nil
        currentDeviceID = nil
    }

    // MARK: - Delegate events

    private enum EngineEvent: Sendable {
        case nowPlayingChanged(ObjectIdentifier)
        case renderingComplete(ObjectIdentifier)
        case endOfAudio
        case error(String)
    }

    private func installBridgeIfNeeded() {
        guard bridge == nil else { return }
        let (stream, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        let bridge = DelegateBridge { event in continuation.yield(event) }
        engine.delegate = bridge
        self.bridge = bridge
        eventPump = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: EngineEvent) async {
        switch event {
        case .nowPlayingChanged(let decoderID):
            guard let armed, decoderID == armed.decoder, armed.generation == generation,
                case .playing = state
            else { return }
            advance(to: decoderID)
            await armGapless()
        case .renderingComplete(let decoderID):
            renderedOut = decoderID
        case .endOfAudio:
            // Конец звука без идентичности принимаем только вслед за концом
            // текущего декодера: событие прежнего pipeline, опоздавшее к
            // новому старту, иначе двигало бы очередь на трек вперёд.
            guard renderedOut == currentDecoderID else { return }
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
                let mine = generation
                try? await Task.sleep(for: .milliseconds(250))
                // Play во время этих 250 мс — новый трек не гасим.
                guard mine == generation else { return }
                await stop()
            }
        case .error(let message):
            if queue.indices.contains(index) {
                await fail(
                    queue[index].track, with: .decodingFailed(message), generation: generation)
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
            if let nowPlaying {
                onEvent(.nowPlayingChanged(ObjectIdentifier(nowPlaying as AnyObject)))
            }
        }

        func audioPlayer(_ audioPlayer: AudioPlayer, renderingComplete decoder: any PCMDecoding) {
            onEvent(.renderingComplete(ObjectIdentifier(decoder as AnyObject)))
        }

        func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
            onEvent(.endOfAudio)
        }

        func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: any Error) {
            onEvent(.error(error.localizedDescription))
        }
    }
}
