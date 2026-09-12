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
    /// Удобная форма для вызывающих, у которых есть сам элемент: берётся его
    /// первое вхождение. Очередь с повторами различает вхождения — см.
    /// `shuffledIndices`.
    public static func shuffled<G: RandomNumberGenerator>(
        items: [PlaybackItem],
        current: PlaybackItem?,
        mode: ShuffleMode,
        using generator: inout G
    ) -> [PlaybackItem] {
        shuffled(
            items: items, currentIndex: current.flatMap { items.firstIndex(of: $0) }, mode: mode,
            using: &generator)
    }

    /// Перемешивает `items`, оставляя вхождение `currentIndex` на первом месте.
    public static func shuffled<G: RandomNumberGenerator>(
        items: [PlaybackItem],
        currentIndex: Int?,
        mode: ShuffleMode,
        using generator: inout G
    ) -> [PlaybackItem] {
        shuffledIndices(items: items, currentIndex: currentIndex, mode: mode, using: &generator)
            .map { items[$0] }
    }

    /// Порядок обхода как перестановка позиций `items`: текущее вхождение
    /// первым, остальное вперемешку. Исключается ровно одна позиция, а не
    /// все копии трека — `[A, B, A]` остаётся тремя элементами.
    /// `.albums` тасует группы по `album_id`, сохраняя порядок треков внутри
    /// группы; треки без альбома считаются каждый сам себе группой.
    public static func shuffledIndices<G: RandomNumberGenerator>(
        items: [PlaybackItem],
        currentIndex: Int?,
        mode: ShuffleMode,
        using generator: inout G
    ) -> [Int] {
        guard mode != .off, !items.isEmpty else { return Array(items.indices) }
        let current = currentIndex.flatMap { items.indices.contains($0) ? $0 : nil }
        let rest = items.indices.filter { $0 != current }

        let shuffledRest: [Int]
        switch mode {
        case .off:
            shuffledRest = rest
        case .tracks:
            shuffledRest = rest.shuffled(using: &generator)
        case .albums:
            var groups: [[Int]] = []
            var indexByAlbum: [Int64: Int] = [:]
            for position in rest {
                guard let albumId = items[position].track.albumId else {
                    groups.append([position])
                    continue
                }
                if let existing = indexByAlbum[albumId] {
                    groups[existing].append(position)
                } else {
                    indexByAlbum[albumId] = groups.count
                    groups.append([position])
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
