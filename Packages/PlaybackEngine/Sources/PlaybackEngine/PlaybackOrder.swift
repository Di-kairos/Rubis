import EscapementCore
import Foundation

/// Что делать, когда очередь кончилась или трек доиграл.
public enum RepeatMode: String, Codable, Sendable, CaseIterable {
    case off
    /// Текущий трек по кругу.
    case track
    /// Очередь по кругу.
    case all
}

/// Перемешивание очереди. Порядок внутри альбома всегда сохраняется —
/// альбом, разложенный вперемешку, это не музыка.
public enum ShuffleMode: String, Codable, Sendable, CaseIterable {
    case off
    /// Треки вперемешку.
    case tracks
    /// Альбомы вперемешку, треки внутри альбома по порядку.
    case albums
}

/// Построение порядка очереди. Чистая функция — тестируется без железа.
public enum PlaybackOrder {
    /// Перемешивает `items`, оставляя `current` на первом месте.
    /// `.albums` тасует группы по `album_id`, сохраняя порядок треков внутри группы;
    /// треки без альбома считаются каждый сам себе группой.
    public static func shuffled<G: RandomNumberGenerator>(
        items: [PlaybackItem],
        current: PlaybackItem?,
        mode: ShuffleMode,
        using generator: inout G
    ) -> [PlaybackItem] {
        guard mode != .off, !items.isEmpty else { return items }
        let rest = items.filter { $0.track.id != current?.track.id }

        let shuffledRest: [PlaybackItem]
        switch mode {
        case .off:
            shuffledRest = rest
        case .tracks:
            shuffledRest = rest.shuffled(using: &generator)
        case .albums:
            var groups: [[PlaybackItem]] = []
            var indexByAlbum: [Int64: Int] = [:]
            for item in rest {
                guard let albumId = item.track.albumId else {
                    groups.append([item])
                    continue
                }
                if let existing = indexByAlbum[albumId] {
                    groups[existing].append(item)
                } else {
                    indexByAlbum[albumId] = groups.count
                    groups.append([item])
                }
            }
            shuffledRest = groups.shuffled(using: &generator).flatMap { $0 }
        }
        return (current.map { [$0] } ?? []) + shuffledRest
    }

    /// Следующая позиция при автопереходе (трек доиграл сам).
    /// nil — очередь кончилась, играть больше нечего.
    public static func next(after index: Int, count: Int, repeatMode: RepeatMode) -> Int? {
        guard count > 0 else { return nil }
        switch repeatMode {
        case .track:
            return index
        case .all:
            return (index + 1) % count
        case .off:
            return index + 1 < count ? index + 1 : nil
        }
    }

    /// Следующая позиция по кнопке. От автоперехода отличается тем, что
    /// `repeat track` не запирает пользователя на одном треке.
    public static func manualNext(after index: Int, count: Int, repeatMode: RepeatMode) -> Int? {
        next(after: index, count: count, repeatMode: repeatMode == .track ? .off : repeatMode)
    }

    /// Предыдущая позиция. По кругу — только при `repeat all`.
    public static func previous(before index: Int, count: Int, repeatMode: RepeatMode) -> Int? {
        guard count > 0 else { return nil }
        if index > 0 { return index - 1 }
        return repeatMode == .all ? count - 1 : nil
    }
}
