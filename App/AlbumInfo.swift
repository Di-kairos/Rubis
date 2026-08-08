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

    init() {
        cacheRoot = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Escapement/album-info", isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    /// Кеш → Wikipedia → Claude. nil — источники не нашлись или выключено;
    /// секция в UI тогда просто не показывается.
    func info(for album: Album) async -> AlbumInfo? {
        guard let id = album.id, let title = nonEmpty(album.title) else { return nil }
        if let cached = readCache(albumId: id) { return cached }

        var result = await fetchWikipedia(title: title, artist: album.albumArtist)
        if result == nil {
            let provider =
                NotesProvider(
                    rawValue: UserDefaults.standard.string(forKey: "notesProvider") ?? ""
                ) ?? .claude
            switch provider {
            case .claude:
                result = await fetchClaude(
                    title: title, artist: album.albumArtist, year: album.year)
            case .deepseek:
                result = await fetchDeepSeek(
                    title: title, artist: album.albumArtist, year: album.year)
            }
        }
        if let result { writeCache(albumId: id, info: result) }
        return result
    }

    // MARK: - Wikipedia

    private func fetchWikipedia(title: String, artist: String?) async -> AlbumInfo? {
        let query = [title, artist ?? "", "album"].joined(separator: " ")
        var search = URLComponents(string: "https://en.wikipedia.org/w/rest.php/v1/search/title")
        search?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "3"),
        ]
        guard let searchURL = search?.url,
            let searchData = try? await data(from: URLRequest(url: searchURL)),
            let pages = try? JSONDecoder().decode(WikiSearch.self, from: searchData).pages,
            let key = pages.first?.key,
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

    private struct WikiSearch: Decodable {
        struct Page: Decodable { let key: String }
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

    private func fetchClaude(title: String, artist: String?, year: Int?) async -> AlbumInfo? {
        guard let apiKey = KeychainStore.load(account: NotesProvider.claude.keychainAccount),
            !apiKey.isEmpty,
            let url = URL(string: "https://api.anthropic.com/v1/messages")
        else { return nil }
        let prompt = linerNotesPrompt(title: title, artist: artist, year: year)

        let body: [String: Any] = [
            "model": "claude-opus-5",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [["role": "user", "content": prompt]],
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let responseData = try? await data(from: request),
            let message = try? JSONDecoder().decode(ClaudeMessage.self, from: responseData),
            message.stopReason != "refusal",
            let text = message.content.first(where: { $0.type == "text" })?.text,
            let clean = nonEmpty(text), clean != "UNKNOWN"
        else { return nil }
        return AlbumInfo(source: .claude, text: clean)
    }

    /// DeepSeek: OpenAI-совместимый chat/completions, Bearer-авторизация.
    private func fetchDeepSeek(title: String, artist: String?, year: Int?) async -> AlbumInfo? {
        guard let apiKey = KeychainStore.load(account: NotesProvider.deepseek.keychainAccount),
            !apiKey.isEmpty,
            let url = URL(string: "https://api.deepseek.com/chat/completions")
        else { return nil }
        let prompt = linerNotesPrompt(title: title, artist: artist, year: year)

        let body: [String: Any] = [
            "model": "deepseek-chat",
            "max_tokens": 1024,
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
            let text = completion.choices.first?.message.content,
            let clean = nonEmpty(text), clean != "UNKNOWN"
        else { return nil }
        return AlbumInfo(source: .deepseek, text: clean)
    }

    private struct DeepSeekCompletion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
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
        guard let data = try? Data(contentsOf: cacheURL(albumId: albumId)) else { return nil }
        return try? JSONDecoder().decode(AlbumInfo.self, from: data)
    }

    private func writeCache(albumId: Int64, info: AlbumInfo) {
        try? FileManager.default.createDirectory(
            at: cacheRoot, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(info) {
            try? data.write(to: cacheURL(albumId: albumId))
        }
    }

    private func data(from request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

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

    static func save(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
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
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
