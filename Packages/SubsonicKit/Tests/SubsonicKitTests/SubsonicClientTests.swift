import Foundation
import Testing

@testable import SubsonicKit

/// Тесты клиента: сеть подменена, ответы — из `Fixtures`.
struct SubsonicClientTests {

    /// Клиент с предсказуемой солью и заранее заданным ответом.
    /// `seen` собирает адреса запросов — по ним проверяются параметры.
    private func makeClient(
        body: String,
        status: Int = 200,
        seen: URLBox = URLBox()
    ) throws -> SubsonicClient {
        try SubsonicClient(
            serverURL: "https://music.example.com",
            username: "di",
            password: "hunter2",
            fetch: { request in
                seen.url = request.url
                let http = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://x")!, statusCode: status,
                    httpVersion: nil, headerFields: nil)!
                return (Data(body.utf8), http)
            },
            makeSalt: { "cafebabe" })
    }

    /// Ссылка на последний запрошенный адрес — тестам нужна изменяемость.
    final class URLBox: @unchecked Sendable {
        var url: URL?
    }

    // MARK: - Аутентификация

    @Test func tokenIsMD5OfPasswordAndSalt() {
        // Эталон посчитан вне Swift: printf 'hunter2cafebabe' | md5
        #expect(
            SubsonicClient.token(password: "hunter2", salt: "cafebabe")
                == "f068c976f1cf619987e30426ea2898d1")
    }

    @Test func queryCarriesTokenAndNeverThePassword() throws {
        let client = try makeClient(body: Fixtures.ping)
        let url = try #require(client.url(endpoint: "ping", query: [:]))
        let query = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let byName = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })

        #expect(byName["u"] == "di")
        #expect(byName["s"] == "cafebabe")
        #expect(byName["t"] == SubsonicClient.token(password: "hunter2", salt: "cafebabe"))
        #expect(byName["v"] == "1.16.1")
        #expect(byName["c"] == "Escapement")
        #expect(byName["f"] == "json")
        #expect(!url.absoluteString.contains("hunter2"))
        #expect(byName["p"] == nil)
    }

    @Test func serverURLWithoutHostIsRejected() {
        #expect(throws: SubsonicError.invalidServerURL) {
            _ = try SubsonicClient(serverURL: "not a server", username: "di", password: "x")
        }
    }

    // MARK: - ping

    @Test func pingSucceedsOnOkStatus() async throws {
        let client = try makeClient(body: Fixtures.ping)
        try await client.ping()
    }

    @Test func pingReportsServerError() async throws {
        let client = try makeClient(body: Fixtures.pingFailed)
        await #expect(
            throws: SubsonicError.server(.init(code: 40, message: "Wrong username or password"))
        ) {
            try await client.ping()
        }
    }

    @Test func httpErrorIsReported() async throws {
        let client = try makeClient(body: Fixtures.ping, status: 502)
        await #expect(throws: SubsonicError.http(502)) {
            try await client.ping()
        }
    }

    @Test func nonJSONAnswerIsMalformed() async throws {
        let client = try makeClient(body: Fixtures.notJSON)
        await #expect(throws: SubsonicError.malformedResponse) {
            try await client.ping()
        }
    }

    // MARK: - Каталог

    @Test func artistsAreFlattenedAcrossIndexLetters() async throws {
        let client = try makeClient(body: Fixtures.artists)
        let artists = try await client.artists()
        #expect(artists.count == 3)
        #expect(artists.first?.name == "All India Radio")
        #expect(artists.last?.id == "ar-3")
    }

    @Test func emptyArtistIndexGivesEmptyList() async throws {
        let client = try makeClient(body: Fixtures.artistsEmpty)
        #expect(try await client.artists().isEmpty)
    }

    @Test func albumPageIsParsed() async throws {
        let seen = URLBox()
        let client = try makeClient(body: Fixtures.albumList, seen: seen)
        let albums = try await client.albums(offset: 500, size: 500)
        #expect(albums.count == 2)
        #expect(albums[0].year == 2019)
        #expect(albums[1].songCount == 30)

        let query = try #require(seen.url?.query)
        #expect(query.contains("type=alphabeticalByName"))
        #expect(query.contains("offset=500"))
    }

    @Test func missingAlbumArrayMeansEndOfList() async throws {
        let client = try makeClient(body: Fixtures.albumListEmpty)
        #expect(try await client.albums().isEmpty)
    }

    @Test func albumCarriesItsSongs() async throws {
        let client = try makeClient(body: Fixtures.album)
        let detail = try await client.album(id: "al-1")
        #expect(detail.album.name == "Eternal")
        #expect(detail.songs.count == 2)
        #expect(detail.songs[0].samplingRate == 44100)
        #expect(detail.songs[0].bitDepth == 24)
        // Старый сервер не присылает расширений OpenSubsonic — формат
        // выяснится после скачивания файла (SPEC §6.2).
        #expect(detail.songs[1].samplingRate == nil)
        #expect(detail.songs[1].discNumber == nil)
    }

    @Test func artistCarriesItsAlbums() async throws {
        let client = try makeClient(body: Fixtures.artist)
        let (artist, albums) = try await client.artist(id: "ar-1")
        #expect(artist.name == "All India Radio")
        #expect(albums.count == 1)
        #expect(albums[0].id == "al-1")
    }

    // MARK: - Тексты ошибок

    @Test func errorsReadAsSentences() {
        #expect(
            SubsonicError.server(.init(code: 40, message: "Wrong username or password"))
                .errorDescription == "Wrong username or password")
        #expect(
            SubsonicError.server(.init(code: 70, message: "Album not found"))
                .errorDescription == "Album not found")
        #expect(
            SubsonicError.server(.init(code: 70, message: nil))
                .errorDescription == "Server refused the request (code 70)")
        #expect(SubsonicError.http(502).errorDescription == "Server answered with HTTP 502")
        #expect(
            SubsonicError.invalidServerURL.errorDescription == "That address is not a server URL")
    }

    // MARK: - Адреса файлов

    @Test func streamURLForbidsTranscoding() throws {
        let client = try makeClient(body: Fixtures.ping)
        let url = try #require(client.streamURL(id: "tr-1"))
        let query = try #require(url.query)
        #expect(query.contains("format=raw"))
        #expect(query.contains("maxBitRate=0"))
        #expect(url.path == "/rest/stream")
    }

    @Test func downloadAndCoverURLsAreBuilt() throws {
        let client = try makeClient(body: Fixtures.ping)
        let download = try #require(client.downloadURL(id: "tr-1"))
        #expect(download.path == "/rest/download")
        #expect(try #require(download.query).contains("id=tr-1"))

        let cover = try #require(client.coverArtURL(id: "al-1", size: 600))
        #expect(cover.path == "/rest/getCoverArt")
        #expect(try #require(cover.query).contains("size=600"))
    }
}
