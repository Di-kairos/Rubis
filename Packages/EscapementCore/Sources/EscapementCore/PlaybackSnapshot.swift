import Foundation

/// Состояние воспроизведения между запусками: что играло, где в очереди и на
/// какой секунде. Живёт в `UserDefaults` — это не библиотека, а настройка сессии.
public struct PlaybackSnapshot: Equatable, Sendable {
    public let trackIds: [Int64]
    public let index: Int
    public let offset: TimeInterval

    public init(trackIds: [Int64], index: Int, offset: TimeInterval) {
        self.trackIds = trackIds
        self.index = index
        self.offset = offset
    }

    private enum Key {
        static let ids = "playback.queue.trackIds"
        static let index = "playback.queue.index"
        static let offset = "playback.queue.offset"
    }

    /// nil, если очереди не было: пустой снимок и отсутствие снимка — одно и то же.
    public static func load(from defaults: UserDefaults) -> PlaybackSnapshot? {
        guard let raw = defaults.array(forKey: Key.ids) as? [Int], !raw.isEmpty else {
            return nil
        }
        let ids = raw.map(Int64.init)
        // Индекс из прошлой версии снимка мог уехать за пределы очереди.
        let index = min(max(defaults.integer(forKey: Key.index), 0), ids.count - 1)
        return PlaybackSnapshot(
            trackIds: ids, index: index,
            offset: max(defaults.double(forKey: Key.offset), 0))
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(trackIds.map(Int.init), forKey: Key.ids)
        defaults.set(index, forKey: Key.index)
        defaults.set(offset, forKey: Key.offset)
    }

    /// Прогресс обновляется чаще, чем состав очереди: индекс и позиция пишутся
    /// вместе, иначе секунда одного трека ложится на снимок другого.
    public static func saveProgress(
        index: Int, offset: TimeInterval, to defaults: UserDefaults
    ) {
        defaults.set(max(index, 0), forKey: Key.index)
        defaults.set(max(offset, 0), forKey: Key.offset)
    }
}
