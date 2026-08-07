import Foundation

/// Порядок сортировки списка треков по колонке (DESIGN §5.2).
/// Сортируем уже загруженный массив: раздел Tracks и так держит библиотеку в памяти.
public enum TrackSort: String, CaseIterable, Sendable {
    case title
    case artist
    case album
    case duration
    case format

    /// Подпись колонки в заголовке.
    public var label: String { rawValue.capitalized }

    /// ponytail: сортировка в памяти — на 100k это сотни миллисекунд на клик;
    /// упрётся в бюджет — уводить в SQL ORDER BY.
    ///
    /// Равные ключи разводит id: порядок детерминирован, и смена направления
    /// не перетасовывает строки внутри группы (иначе выделение «прыгает»).
    public static func sorted(_ rows: [SearchHit], by field: TrackSort, ascending: Bool)
        -> [SearchHit]
    {
        rows.sorted { lhs, rhs in
            let order = compare(lhs, rhs, by: field)
            if order == .orderedSame { return lhs.id < rhs.id }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private static func compare(_ lhs: SearchHit, _ rhs: SearchHit, by field: TrackSort)
        -> ComparisonResult
    {
        switch field {
        case .title:
            return text(lhs.track.title, rhs.track.title)
        case .artist:
            return text(lhs.artistName ?? "", rhs.artistName ?? "")
        case .album:
            return text(lhs.albumTitle ?? "", rhs.albumTitle ?? "")
        case .format:
            return text(lhs.track.codec, rhs.track.codec)
        case .duration:
            let (a, b) = (lhs.track.duration, rhs.track.duration)
            if a == b { return .orderedSame }
            return a < b ? .orderedAscending : .orderedDescending
        }
    }

    /// Человеческое сравнение: регистр и диакритика не двигают строку в конец,
    /// числа в названиях идут по значению («Track 2» перед «Track 10»).
    private static func text(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedStandardCompare(rhs)
    }
}
