import Foundation

/// Одно исходящее соединение приложения.
public struct NetworkEvent: Codable, Sendable, Equatable {
    public let date: Date
    /// Хост, к которому обращались — без пути и параметров: в пути могут
    /// оказаться название альбома или id трека, а журнал не место для них.
    public let host: String
    /// Зачем ходили: «Album notes», «Update check», «Subsonic».
    public let purpose: String
    public let succeeded: Bool
    public let bytes: Int

    public init(date: Date, host: String, purpose: String, succeeded: Bool, bytes: Int) {
        self.date = date
        self.host = host
        self.purpose = purpose
        self.succeeded = succeeded
        self.bytes = bytes
    }
}

/// Строка панели: один хост со сводкой по нему.
public struct NetworkHostSummary: Sendable, Equatable, Identifiable {
    public var id: String { host }
    public let host: String
    /// Все причины обращений к этому хосту, по алфавиту.
    public let purposes: [String]
    public let count: Int
    public let failures: Int
    public let bytes: Int
    public let last: Date
}

/// Журнал исходящих соединений (SPEC §1.2: по умолчанию их ноль — и это
/// должно быть видно, а не обещано на словах).
///
/// Журнал ведётся файлом, а не таблицей: схема БД после фазы 2 меняется
/// только с ведома владельца, а этой записи там и не место.
public actor NetworkLedger {
    private let fileURL: URL
    /// Сколько последних записей держим. Журнал — свидетельство, а не история
    /// на века: старое вытесняется, счётчики за всё время живут отдельно.
    private let limit: Int
    private var loaded: [NetworkEvent]?

    public init(fileURL: URL, limit: Int = 1000) {
        self.fileURL = fileURL
        self.limit = limit
    }

    public func record(host: String, purpose: String, succeeded: Bool, bytes: Int) {
        guard !host.isEmpty else { return }
        var events = load()
        events.append(
            NetworkEvent(
                date: Date(), host: host, purpose: purpose, succeeded: succeeded, bytes: bytes))
        if events.count > limit { events.removeFirst(events.count - limit) }
        loaded = events
        save(events)
    }

    public func events() -> [NetworkEvent] { load() }

    public func summary() -> [NetworkHostSummary] { Self.summarize(load()) }

    public func clear() {
        loaded = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Свод по хостам: чаще всего беспокоящий — сверху. Чистая функция,
    /// поэтому проверяется тестами без файлов и сети.
    public static func summarize(_ events: [NetworkEvent]) -> [NetworkHostSummary] {
        Dictionary(grouping: events, by: \.host)
            .map { host, group in
                NetworkHostSummary(
                    host: host,
                    purposes: Set(group.map(\.purpose)).sorted(),
                    count: group.count,
                    failures: group.filter { !$0.succeeded }.count,
                    bytes: group.reduce(0) { $0 + $1.bytes },
                    last: group.map(\.date).max() ?? .distantPast)
            }
            .sorted { ($0.count, $1.host) > ($1.count, $0.host) }
    }

    // MARK: - Файл

    private func load() -> [NetworkEvent] {
        if let loaded { return loaded }
        guard let data = try? Data(contentsOf: fileURL),
            let events = try? JSONDecoder().decode([NetworkEvent].self, from: data)
        else {
            loaded = []
            return []
        }
        loaded = events
        return events
    }

    /// ponytail: файл переписывается целиком на каждую запись. При лимите в
    /// тысячу событий это десятки килобайт и единицы запросов в час — если
    /// журнал когда-нибудь станет горячим, дописывать построчно.
    private func save(_ events: [NetworkEvent]) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
