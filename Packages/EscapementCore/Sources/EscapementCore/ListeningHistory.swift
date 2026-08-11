import Foundation

/// Одно засчитанное прослушивание.
///
/// Имена артиста и альбома лежат строками, а не ссылками: история переживает
/// пересканирование библиотеки и удаление файла — то, что было прослушано,
/// прослушано.
public struct PlayEvent: Codable, Sendable, Equatable {
    public let date: Date
    public let trackId: Int64
    public let title: String
    public let artist: String
    public let album: String
    /// Сколько секунд трека реально прозвучало к моменту засчёта.
    public let seconds: Double

    public init(
        date: Date, trackId: Int64, title: String, artist: String, album: String, seconds: Double
    ) {
        self.date = date
        self.trackId = trackId
        self.title = title
        self.artist = artist
        self.album = album
        self.seconds = seconds
    }
}

/// Строка сводки: артист или трек с числом прослушиваний.
public struct HistoryTally: Sendable, Equatable, Identifiable {
    public var id: String { "\(name)\u{1F}\(detail)" }
    public let name: String
    /// Подпись под именем: у трека — артист, у артиста — пусто.
    public let detail: String
    public let count: Int
    public let seconds: Double
    public let last: Date

    public init(name: String, detail: String, count: Int, seconds: Double, last: Date) {
        self.name = name
        self.detail = detail
        self.count = count
        self.seconds = seconds
        self.last = last
    }
}

/// Приватная история прослушиваний (SPEC §1.2: никаких скробблов наружу).
///
/// Как и журнал соединений, ведётся файлом: схема БД после фазы 2 меняется
/// только с ведома владельца, а истории место рядом с журналом, а не в
/// каталоге библиотеки.
public actor ListeningHistory {
    private let fileURL: URL
    /// Потолок записей. При одном событии на трек это годы прослушивания.
    private let limit: Int
    private var loaded: [PlayEvent]?

    public init(fileURL: URL, limit: Int = 20_000) {
        self.fileURL = fileURL
        self.limit = limit
    }

    public func record(
        trackId: Int64, title: String, artist: String, album: String, seconds: Double
    ) {
        var events = load()
        events.append(
            PlayEvent(
                date: Date(), trackId: trackId, title: title, artist: artist, album: album,
                seconds: seconds))
        if events.count > limit { events.removeFirst(events.count - limit) }
        loaded = events
        save(events)
    }

    public func events() -> [PlayEvent] { load() }

    public func clear() {
        loaded = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Правило засчёта

    /// Прослушивание засчитывается на половине трека или на четвёртой минуте —
    /// что наступит раньше. Правило привычное (last.fm), и оно не наказывает
    /// длинные вещи: получасовой сет засчитывается, не досиживая до конца.
    public static func counts(listened: Double, duration: Double) -> Bool {
        listened >= 240 || (duration > 0 && listened >= duration / 2)
    }

    // MARK: - Сводки (чистые функции — тестируются без файлов)

    public static func topArtists(_ events: [PlayEvent], limit: Int = 10) -> [HistoryTally] {
        tally(events, key: \.artist, name: \.artist, detail: { _ in "" }, limit: limit)
    }

    /// Трек опознаётся парой «название + артист»: одноимённые песни разных
    /// исполнителей — разные строки, а переезд файла историю не дробит.
    public static func topTracks(_ events: [PlayEvent], limit: Int = 10) -> [HistoryTally] {
        tally(
            events, key: { "\($0.title)\u{1F}\($0.artist)" }, name: \.title, detail: \.artist,
            limit: limit)
    }

    /// События не старше даты — период выбирается в UI.
    public static func since(_ date: Date, in events: [PlayEvent]) -> [PlayEvent] {
        events.filter { $0.date >= date }
    }

    private static func tally(
        _ events: [PlayEvent], key: (PlayEvent) -> String, name: (PlayEvent) -> String,
        detail: (PlayEvent) -> String, limit: Int
    ) -> [HistoryTally] {
        Dictionary(grouping: events, by: key)
            .map { _, group in
                HistoryTally(
                    name: group.first.map(name) ?? "",
                    detail: group.first.map(detail) ?? "",
                    count: group.count,
                    seconds: group.reduce(0) { $0 + $1.seconds },
                    last: group.map(\.date).max() ?? .distantPast)
            }
            // Частое — сверху; при равенстве побеждает то, что слушали позже.
            .sorted { ($0.count, $0.last) > ($1.count, $1.last) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Файл

    private func load() -> [PlayEvent] {
        if let loaded { return loaded }
        guard let data = try? Data(contentsOf: fileURL),
            let events = try? JSONDecoder().decode([PlayEvent].self, from: data)
        else {
            loaded = []
            return []
        }
        loaded = events
        return events
    }

    /// ponytail: файл переписывается целиком на каждую запись. Событие
    /// рождается раз в несколько минут, так что даже на потолке в 20k это
    /// пара мегабайт изредка — дописывать построчно, если станет заметно.
    private func save(_ events: [PlayEvent]) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
