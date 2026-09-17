import Foundation

/// Состояние воспроизведения между запусками: что играло, где в очереди и на
/// какой секунде. Живёт в `UserDefaults` — это не библиотека, а настройка сессии.
public struct PlaybackSnapshot: Equatable, Sendable {
    /// Треки в исходном порядке — том, что вернёт выключенный shuffle.
    public let trackIds: [Int64]
    /// Позиция в очереди → позиция в `trackIds`. Без shuffle — тождество.
    public let order: [Int]
    /// Позиция в очереди (в `order`), а не в `trackIds`.
    public let index: Int
    public let offset: TimeInterval

    public init(trackIds: [Int64], order: [Int]? = nil, index: Int, offset: TimeInterval) {
        self.trackIds = trackIds
        // Перестановка из чужой версии или битая — очередь идёт как есть.
        let valid = order.map { $0.sorted() == Array(trackIds.indices) } ?? false
        self.order = valid ? order ?? [] : Array(trackIds.indices)
        self.index = index
        self.offset = offset
    }

    private enum Key {
        static let ids = "playback.queue.trackIds"
        static let order = "playback.queue.order"
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
            trackIds: ids, order: defaults.array(forKey: Key.order) as? [Int], index: index,
            offset: max(defaults.double(forKey: Key.offset), 0))
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(trackIds.map(Int.init), forKey: Key.ids)
        defaults.set(order, forKey: Key.order)
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

    /// Снимок без выпавших треков (файл пропал, источник отключён): порядок
    /// переносится на выживших, индекс — по числу выживших до него в очереди.
    /// Выпал сам текущий — встаём на следующего выжившего с начала: чужому
    /// треку его секунда не достаётся.
    public func keeping(_ survives: (Int64) -> Bool) -> PlaybackSnapshot {
        let kept = trackIds.indices.filter { survives(trackIds[$0]) }
        var renumbered: [Int: Int] = [:]
        for (new, old) in kept.enumerated() { renumbered[old] = new }
        let current = order.indices.contains(index) ? order[index] : nil
        let before = order.prefix(index).filter { renumbered[$0] != nil }.count
        let currentSurvived = current.map { renumbered[$0] != nil } ?? false
        return PlaybackSnapshot(
            trackIds: kept.map { trackIds[$0] },
            order: order.compactMap { renumbered[$0] },
            index: before,
            offset: currentSurvived ? offset : 0)
    }
}
