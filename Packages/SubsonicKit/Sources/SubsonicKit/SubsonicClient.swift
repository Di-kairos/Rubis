import CryptoKit
import EscapementCore
import Foundation

/// Клиент OpenSubsonic (SPEC §6.1). Без состояния: каждый запрос сам считает
/// соль и токен, поэтому клиент можно свободно копировать между акторами.
///
/// Пароль живёт только здесь и в Keychain приложения — в UserDefaults, БД и
/// логах его нет (SPEC §6.1). В сеть уходит `md5(password + salt)`.
public struct SubsonicClient: Sendable {
    /// Транспорт запроса. Подменяется в тестах, чтобы они не ходили в сеть.
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Версия протокола, минимальная совместимость по SPEC §6.1.
    static let apiVersion = "1.16.1"
    /// Имя клиента в параметре `c` — сервер показывает его в своих логах.
    static let clientName = "Escapement"

    private let baseURL: URL
    private let username: String
    private let password: String
    private let fetch: Fetch
    private let makeSalt: @Sendable () -> String

    /// - Parameters:
    ///   - serverURL: адрес сервера как его ввёл владелец (`https://music.example.com`).
    ///   - makeSalt: генератор соли; подменяется в тестах ради предсказуемого токена.
    public init(
        serverURL: String,
        username: String,
        password: String,
        fetch: @escaping Fetch = SubsonicClient.urlSessionFetch,
        makeSalt: @escaping @Sendable () -> String = SubsonicClient.randomSalt
    ) throws {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host != nil else {
            throw SubsonicError.invalidServerURL
        }
        self.baseURL = url
        self.username = username
        self.password = password
        self.fetch = fetch
        self.makeSalt = makeSalt
    }

    /// Хост сервера — для журнала соединений: путь и параметры туда не идут.
    public var host: String { baseURL.host ?? "" }

    // MARK: - Эндпоинты

    /// Проверка соединения при сохранении настроек. Молчит при успехе,
    /// бросает `SubsonicError` при любой беде — UI показывает результат явно.
    public func ping() async throws {
        _ = try await request(EmptyPayload.self, endpoint: "ping")
    }

    /// Всё дерево артистов одним запросом (`getArtists`).
    public func artists() async throws -> [SubsonicArtist] {
        try await request(ArtistsPayload.self, endpoint: "getArtists").flattened
    }

    /// Альбомы артиста (`getArtist`).
    public func artist(id: String) async throws -> (SubsonicArtist, [SubsonicAlbum]) {
        let payload = try await request(
            ArtistPayload.self, endpoint: "getArtist", query: ["id": id])
        return (payload.artist.artist, payload.artist.album ?? [])
    }

    /// Страница инвентаризации альбомов (`getAlbumList2`, `alphabeticalByName`).
    /// Пустой ответ означает конец списка.
    public func albums(offset: Int = 0, size: Int = 500) async throws -> [SubsonicAlbum] {
        let payload = try await request(
            AlbumListPayload.self, endpoint: "getAlbumList2",
            query: [
                "type": "alphabeticalByName",
                "size": String(size),
                "offset": String(offset),
            ])
        return payload.albumList2.album ?? []
    }

    /// Альбом с треками (`getAlbum`).
    public func album(id: String) async throws -> SubsonicAlbumDetail {
        let payload = try await request(
            AlbumPayload.self, endpoint: "getAlbum", query: ["id": id])
        return SubsonicAlbumDetail(album: payload.album.album, songs: payload.album.song ?? [])
    }

    // MARK: - Адреса файлов

    /// Обложка альбома или трека (`getCoverArt`).
    public func coverArtURL(id: String, size: Int? = nil) -> URL? {
        var query = ["id": id]
        if let size { query["size"] = String(size) }
        return url(endpoint: "getCoverArt", query: query)
    }

    /// Байты обложки (`getCoverArt`). Без `size` сервер отдаёт оригинал —
    /// ровно то, что кладёт в кэш сканер локальных папок (SPEC §5.4).
    ///
    /// Ответ не разбирается как JSON: при ошибке сервер всё равно шлёт конверт,
    /// поэтому картинку от отказа отличаем по типу содержимого.
    public func coverArt(id: String, size: Int? = nil) async throws -> Data {
        guard let url = coverArtURL(id: id, size: size) else {
            throw SubsonicError.invalidServerURL
        }
        let (data, http) = try await fetch(URLRequest(url: url))
        guard (200..<300).contains(http.statusCode) else {
            throw SubsonicError.http(http.statusCode)
        }
        let type = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard type.hasPrefix("image/") else {
            throw SubsonicError.malformedResponse
        }
        return data
    }

    /// Поток без транскодирования. `format=raw` и `maxBitRate=0` обязательны:
    /// любое перекодирование на сервере убивает bit-perfect (SPEC §6.1).
    public func streamURL(id: String) -> URL? {
        url(endpoint: "stream", query: ["id": id, "format": "raw", "maxBitRate": "0"])
    }

    /// Полная копия файла — основной путь воспроизведения (download-then-play, SPEC §6.2).
    public func downloadURL(id: String) -> URL? {
        url(endpoint: "download", query: ["id": id])
    }

    // MARK: - Запрос

    private func request<Payload: Decodable & Sendable>(
        _ type: Payload.Type,
        endpoint: String,
        query: [String: String] = [:]
    ) async throws -> Payload {
        guard let url = url(endpoint: endpoint, query: query) else {
            throw SubsonicError.invalidServerURL
        }
        let (data, http) = try await fetch(URLRequest(url: url))
        guard (200..<300).contains(http.statusCode) else {
            throw SubsonicError.http(http.statusCode)
        }
        let envelope: SubsonicEnvelope<Payload>
        do {
            envelope = try JSONDecoder().decode(SubsonicEnvelope<Payload>.self, from: data)
        } catch {
            throw SubsonicError.malformedResponse
        }
        guard envelope.response.status == "ok" else {
            throw SubsonicError.server(
                envelope.response.error ?? SubsonicServerError(code: 0, message: nil))
        }
        guard let payload = envelope.response.payload else {
            throw SubsonicError.malformedResponse
        }
        return payload
    }

    /// Полный адрес эндпоинта с параметрами аутентификации.
    func url(endpoint: String, query: [String: String]) -> URL? {
        let salt = makeSalt()
        var items = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: Self.token(password: password, salt: salt)),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: Self.apiVersion),
            URLQueryItem(name: "c", value: Self.clientName),
            URLQueryItem(name: "f", value: "json"),
        ]
        items.append(contentsOf: query.sorted { $0.key < $1.key }.map(URLQueryItem.init))

        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/\(endpoint)"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = items
        return components?.url
    }

    /// `t = md5(password + salt)` — пароль в сеть не уходит (SPEC §6.1).
    static func token(password: String, salt: String) -> String {
        let digest = Insecure.MD5.hash(data: Data((password + salt).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Соль на запрос: 16 шестнадцатеричных знаков.
    public static let randomSalt: @Sendable () -> String = {
        (0..<16).map { _ in String("0123456789abcdef".randomElement() ?? "0") }.joined()
    }

    /// Транспорт по умолчанию — общий `URLSession`.
    public static let urlSessionFetch: Fetch = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SubsonicError.malformedResponse
        }
        return (data, http)
    }
}
