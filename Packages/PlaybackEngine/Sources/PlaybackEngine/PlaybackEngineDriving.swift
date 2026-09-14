import CoreAudio
import Foundation
import SFBAudioEngine

/// Всё, что `Player` спрашивает у движка.
///
/// Отдельный протокол нужен ради порядка событий у стыка: decoding thread
/// забирает заряженный декодер в active задолго до того, как он дозвучал, и
/// `clearQueue` такой декодер уже не достаёт. Проверить это ушами нельзя —
/// нужен управляемый адаптер, который в тесте переводит декодер в active
/// ровно между проверкой и очисткой (R03, перепроверка аудита 13.09.2026).
protocol PlaybackEngineDriving: AnyObject {
    /// Декодер, который движок декодирует прямо сейчас.
    var nowPlayingID: ObjectIdentifier? { get }
    /// Очередь движка пуста — заряженного перехода в ней не осталось.
    var queueIsEmpty: Bool { get }
    /// Часы текущего трека: позиция и длительность.
    var currentTime: TimeInterval? { get }
    var totalTime: TimeInterval? { get }

    func play(_ decoder: any PCMDecoding) throws
    func enqueue(_ decoder: any PCMDecoding) throws
    func clearQueue()
    @discardableResult func pause() -> Bool
    @discardableResult func resume() -> Bool
    func stop()
    @discardableResult func seek(time: TimeInterval) -> Bool
    func setOutputDeviceID(_ id: AudioObjectID) throws
    /// Делегат событий движка. У фальшивого адаптера событий нет — он их шлёт сам.
    func install(delegate: AnyObject?)
}

/// Боевой адаптер: тонкая обёртка над `AudioPlayer`, без своей логики.
final class SFBEngineAdapter: PlaybackEngineDriving {
    private let player = AudioPlayer()

    var nowPlayingID: ObjectIdentifier? {
        player.nowPlaying.map { ObjectIdentifier($0 as AnyObject) }
    }
    var queueIsEmpty: Bool { player.queueIsEmpty }
    var currentTime: TimeInterval? { player.time?.current }
    var totalTime: TimeInterval? { player.time?.total }

    func play(_ decoder: any PCMDecoding) throws { try player.play(decoder) }
    func enqueue(_ decoder: any PCMDecoding) throws { try player.enqueue(decoder) }
    func clearQueue() { player.clearQueue() }
    @discardableResult func pause() -> Bool { player.pause() }
    @discardableResult func resume() -> Bool { player.resume() }
    func stop() { player.stop() }
    @discardableResult func seek(time: TimeInterval) -> Bool { player.seek(time: time) }
    func setOutputDeviceID(_ id: AudioObjectID) throws { try player.setOutputDeviceID(id) }
    func install(delegate: AnyObject?) { player.delegate = delegate as? AudioPlayer.Delegate }
}
