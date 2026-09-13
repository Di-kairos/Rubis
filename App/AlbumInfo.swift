import EscapementCore
import Foundation
import Security

/// Краткая аннотация альбома (D-008): Wikipedia как база, Claude API как
/// fallback. Opt-in (Settings → General), результат кешируется навсегда —
/// сеть трогается один раз на альбом.
struct AlbumInfo: Codable, Sendable, Equatable {
    enum Source: String, Codable, Sendable {
        case wikipedia
        case claude
        case deepseek
    }

    let source: Source
    let text: String
}

/// Писатель fallback-заметок — выбор владельца (Settings → General).
enum NotesProvider: String, CaseIterable, Identifiable {
    case claude
    case deepseek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .deepseek: return "DeepSeek"
        }
    }

    /// Отдельный ключ в Keychain на провайдера.
    var keychainAccount: String {
        switch self {
        case .claude: return "claude-api-key"
        case .deepseek: return "deepseek-api-key"
        }
    }
}

/// Актор: сериализует сетевые походы и файловый кеш.
actor AlbumInfoService {
    private let cacheRoot: URL
    private let session: URLSession
    /// Ключи читаются из связки один раз за запуск: писатель спрашивается
    /// на каждый новый альбом, а каждое обращение к Keychain — потенциальный
    /// диалог. Живёт в акторе, поэтому без замков и глобального состояния.
    private var keyCache: [NotesProvider: String] = [:]
    /// Журнал соединений (SPEC §1.2): каждый запрос заметок в нём виден.
    private let ledger: NetworkLedger
    /// Идущие запросы по альбому: быстрое A→B→A ждёт первый, а не шлёт второй.
    private var inFlight: [Int64: Task<AlbumInfo?, Never>] = [:]
    /// Недавние промахи: альбом, о котором нигде ничего нет, не спрашивается
    /// заново на каждый переход между его треками.
    private var misses: [Int64: Date] = [:]
    private static let missTTL: TimeInterval = 600

    init(ledger: NetworkLedger) {
        self.ledger = ledger
        cacheRoot = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Escapement/album-info", isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    /// Кеш → Wikipedia → писатель (Claude/DeepSeek). Порядок вернулся к D-008
    /// (решение владельца): справка приходит за доли секунды, а модель сочиняет
    /// liner notes десятками секунд — платить этим ожиданием за каждый альбом,
    /// у которого статья и так есть, незачем. Писатель берётся за то, чего в
    /// Wikipedia нет.
    /// nil — не нашлось ни там, ни там; секция в UI тогда не показывается.
    func info(for album: Album) async -> AlbumInfo? {
        guard let id = album.id, let title = nonEmpty(album.title) else { return nil }
        if let cached = readCache(albumId: id) { return cached }
        if let missed = misses[id], Date().timeIntervalSince(missed) < Self.missTTL {
            return nil
        }
        if let running = inFlight[id] { return await running.value }
        let task = Task { [weak self] () -> AlbumInfo? in
            guard let self else { return nil }
            return await self.fetch(albumId: id, title: title, album: album)
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        return await task.value
    }

    private func fetch(albumId id: Int64, title: String, album: Album) async -> AlbumInfo? {
        guard Self.notesAllowed else { return nil }
        var result = await fetchWikipedia(title: title, artist: album.albumArtist)
        // Пока ждали Wikipedia, заметки могли выключить: следующий шаг —
        // платный запрос писателю, и начинать его уже нельзя.
        guard Self.notesAllowed else { return nil }
        if result == nil {
            switch Self.selectedProvider {
            case .claude:
                result = await fetchClaude(
                    title: title, artist: album.albumArtist, year: album.year)
            case .deepseek:
                result = await fetchDeepSeek(
                    title: title, artist: album.albumArtist, year: album.year)
            }
        }
        if let result {
            writeCache(albumId: id, info: result)
            misses[id] = nil
        } else {
            misses[id] = Date()
        }
        return result
    }

    /// Выбранный писатель (Settings → Album notes).
    static var selectedProvider: NotesProvider {
        NotesProvider(rawValue: UserDefaults.standard.string(forKey: "notesProvider") ?? "")
            ?? .claude
    }

    /// Ключ писателя на месте? Пустая полоса заметок должна уметь объяснить
    /// себя словами, а не молчать (та же рамка, что у отказа по частоте).
    func writerKeyIsSet() -> Bool { apiKey(for: Self.selectedProvider) != nil }

    // MARK: - Wikipedia

    /// `search/page` (полнотекстовый), не `search/title`: заголовок статьи
    /// редко содержит артиста — «Adam's Apple (album)» по title-поиску не
    /// находился вообще. Из трёх кандидатов берём первый, у которого в
    /// коротком описании есть «album» (у статей об альбомах это «1967 studio
    /// album by …»), иначе первый — так артист-страница не подменяет альбом.
    private func fetchWikipedia(title: String, artist: String?) async -> AlbumInfo? {
        let query = [title, artist ?? "", "album"].joined(separator: " ")
        var search = URLComponents(string: "https://en.wikipedia.org/w/rest.php/v1/search/page")
        search?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "3"),
        ]
        guard let searchURL = search?.url,
            let searchData = try? await data(from: URLRequest(url: searchURL)),
            let pages = try? JSONDecoder().decode(WikiSearch.self, from: searchData).pages,
            let key = albumPage(in: pages, artist: artist)?.key,
            let summaryURL = URL(
                string: "https://en.wikipedia.org/api/rest_v1/page/summary/"
                    + (key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key))
        else { return nil }

        guard let summaryData = try? await data(from: URLRequest(url: summaryURL)),
            let summary = try? JSONDecoder().decode(WikiSummary.self, from: summaryData),
            summary.type == "standard",
            let extract = nonEmpty(summary.extract),
            extract.count >= 150
        else { return nil }
        return AlbumInfo(source: .wikipedia, text: extract)
    }

    /// Только страницы, чьё описание говорит «album»; при известном артисте —
    /// сперва та, где он назван. Первый попавшийся результат без этой
    /// проверки подменял альбом артистом или одноимённым фильмом, и это
    /// уходило в вечный кеш.
    private func albumPage(in pages: [WikiSearch.Page], artist: String?) -> WikiSearch.Page? {
        let albums = pages.filter {
            $0.description?.localizedCaseInsensitiveContains("album") == true
        }
        if let artist = nonEmpty(artist),
            let match = albums.first(where: {
                $0.description?.localizedCaseInsensitiveContains(artist) == true
            })
        {
            return match
        }
        return albums.first
    }

    private struct WikiSearch: Decodable {
        struct Page: Decodable {
            let key: String
            let description: String?
        }
        let pages: [Page]
    }

    private struct WikiSummary: Decodable {
        let type: String?
        let extract: String?
    }

    // MARK: - LLM fallback (Claude / DeepSeek — выбор владельца)

    private func linerNotesPrompt(title: String, artist: String?, year: Int?) -> String {
        var prompt = "Write 2-3 short paragraphs of liner notes about the album \"\(title)\""
        if let artist { prompt += " by \(artist)" }
        if let year { prompt += " (\(year))" }
        prompt +=
            ". Cover why the record matters, who plays on it, and what to listen for. "
            + "Plain prose only — no markdown, no asterisks, no headings, no lists. "
            + "If you don't know this album, reply with exactly UNKNOWN."
        return prompt
    }

    private let systemPrompt =
        "You write concise, knowledgeable liner notes for a personal hi-fi music player."

    /// Ключ сменили в настройках — перечитать из связки при следующем запросе.
    func forgetKeys() {
        keyCache.removeAll()
    }

    /// Ключ провайдера: из связки один раз, дальше из памяти процесса.
    private func apiKey(for provider: NotesProvider) -> String? {
        if let cached = keyCache[provider] { return cached }
        guard let key = KeychainStore.load(account: provider.keychainAccount), !key.isEmpty
        else { return nil }
        keyCache[provider] = key
        return key
    }

    private func fetchClaude(title: String, artist: String?, year: Int?) async -> AlbumInfo? {
        guard let apiKey = apiKey(for: .claude),
            let url = URL(string: "https://api.anthropic.com/v1/messages")
        else { return nil }
        let prompt = linerNotesPrompt(title: title, artist: artist, year: year)

        // 4096: с 1024 ответ обрезался на полуслове и попадал в кеш (0.8.0).
        let body: [String: Any] = [
            "model": "claude-opus-5",
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [["role": "user", "content": prompt]],
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // end_turn строго: обрезанный max_tokens'ом текст в кеш не пускаем.
        guard let responseData = try? await data(from: request),
            let message = try? JSONDecoder().decode(ClaudeMessage.self, from: responseData),
            message.stopReason == "end_turn",
            let text = message.content.first(where: { $0.type == "text" })?.text,
            let clean = nonEmpty(text), clean != "UNKNOWN"
        else { return nil }
        return AlbumInfo(source: .claude, text: clean)
    }

    /// DeepSeek: OpenAI-совместимый chat/completions, Bearer-авторизация.
    private func fetchDeepSeek(title: String, artist: String?, year: Int?) async -> AlbumInfo? {
        guard let apiKey = apiKey(for: .deepseek),
            let url = URL(string: "https://api.deepseek.com/chat/completions")
        else { return nil }
        let prompt = linerNotesPrompt(title: title, artist: artist, year: year)

        let body: [String: Any] = [
            "model": "deepseek-chat",
            "max_tokens": 4096,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt],
            ],
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let responseData = try? await data(from: request),
            let completion = try? JSONDecoder().decode(
                DeepSeekCompletion.self, from: responseData),
            let choice = completion.choices.first,
            choice.finishReason == "stop",
            let text = choice.message.content,
            let clean = nonEmpty(text), clean != "UNKNOWN"
        else { return nil }
        return AlbumInfo(source: .deepseek, text: clean)
    }

    private struct DeepSeekCompletion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }
        let choices: [Choice]
    }

    private struct ClaudeMessage: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    // MARK: - Cache & helpers

    private func cacheURL(albumId: Int64) -> URL {
        cacheRoot.appendingPathComponent("\(albumId).json")
    }

    private func readCache(albumId: Int64) -> AlbumInfo? {
        guard let data = try? Data(contentsOf: cacheURL(albumId: albumId)),
            let info = try? JSONDecoder().decode(AlbumInfo.self, from: data)
        else { return nil }
        // Самолечение кеша: до 0.8.1 обрезанный max_tokens'ом ответ LLM
        // кешировался навсегда. Заметка без конца предложения — перезапросить.
        if info.source != .wikipedia, !endsAsSentence(info.text) { return nil }
        return info
    }

    /// ponytail: эвристика конца предложения — ловит обрезку max_tokens,
    /// точной проверки завершённости у кешированного текста нет.
    private func endsAsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last
        else { return false }
        return ".!?…\"'»)".contains(last)
    }

    private func writeCache(albumId: Int64, info: AlbumInfo) {
        try? FileManager.default.createDirectory(
            at: cacheRoot, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(info) {
            try? data.write(to: cacheURL(albumId: albumId))
        }
    }

    /// Заметки об альбоме разрешены прямо сейчас?
    ///
    /// Разрешение спрашивается у КАЖДОЙ двери наружу, а не один раз на экране:
    /// SwiftUI отменяет задачу экрана, но сервис живёт своей неструктурированной
    /// `Task`, и промах Wikipedia успевал отправить запрос писателю уже после
    /// выключения (R07, перепроверка аудита 13.09.2026).
    private static var notesAllowed: Bool {
        UserDefaults.standard.object(forKey: "albumNotes") as? Bool ?? false
    }

    /// Единственная дверь наружу у заметок — здесь же запись в журнал,
    /// поэтому «незаписанного» запроса не бывает.
    private func data(from request: URLRequest) async throws -> Data {
        // Отзыв разрешения догоняет запрос до отправки байтов.
        guard Self.notesAllowed else { throw CancellationError() }
        let host = request.url?.host ?? ""
        let result: Result<(Data, URLResponse), any Error>
        do {
            result = .success(try await session.data(for: request))
        } catch {
            result = .failure(error)
        }

        switch result {
        case .success(let (data, response)):
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            await ledger.record(
                host: host, purpose: Self.ledgerPurpose, succeeded: ok, bytes: data.count)
            guard ok else { throw URLError(.badServerResponse) }
            return data
        case .failure(let error):
            // Сеть не ответила вовсе — для журнала это тоже событие.
            await ledger.record(
                host: host, purpose: Self.ledgerPurpose, succeeded: false, bytes: 0)
            throw error
        }
    }

    static let ledgerPurpose = "Album notes"

    private func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// API-ключи — только в Keychain (§7: секреты не в UserDefaults и не в git).
/// `account` — ключ провайдера (NotesProvider.keychainAccount).
enum KeychainStore {
    private static let service = "com.dikairos.escapement"

    /// Обновление на месте; добавление — только когда записи нет (тот же
    /// урок, что у пароля Subsonic: Delete→Add терял ключ при отказе связки
    /// и стирал выданное записи «Always Allow»).
    @discardableResult
    static func save(_ value: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard !value.isEmpty, let data = value.data(using: .utf8) else {
            return SecItemDelete(query as CFDictionary)
        }
        let update = SecItemUpdate(
            query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard update == errSecItemNotFound else { return update }
        var add = query
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else { return nil }
        // Чтение НИЧЕГО не меняет в связке. Пересохранение «для усыновления»
        // (0.8.3) делало ровно обратное обещанному: «Always Allow» выдаётся
        // на конкретную запись, а мы её тут же удаляли и создавали заново —
        // разрешение исчезало вместе со старой записью, и диалог возвращался
        // при каждом чтении.
        return value
    }
}
