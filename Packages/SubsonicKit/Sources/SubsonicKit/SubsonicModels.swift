import Foundation

/// Ответ сервера всегда завёрнут в `subsonic-response` (SPEC §6.1).
/// Полезная нагрузка каждого эндпоинта — отдельный тип `Payload`.
struct SubsonicEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let response: Response

    struct Response: Decodable, Sendable {
        let status: String
        let version: String
        let error: SubsonicServerError?
        let payload: Payload?

        private enum CodingKeys: String, CodingKey {
            case status, version, error
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decode(String.self, forKey: .status)
            version = try container.decode(String.self, forKey: .version)
            error = try container.decodeIfPresent(SubsonicServerError.self, forKey: .error)
            // Полезная нагрузка лежит рядом с status/version под своим ключом
            // (`artists`, `album`, …) — тип сам знает, как себя достать.
            payload = try? Payload(from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case response = "subsonic-response"
    }
}

/// Ошибка, о которой сообщил сам сервер (`status = "failed"`).
public struct SubsonicServerError: Decodable, Sendable, Equatable {
    public let code: Int
    public let message: String?
}

/// Всё, что может пойти не так у клиента.
public enum SubsonicError: Error, Sendable, Equatable {
    /// Сервер ответил `status = "failed"` с кодом (40 — неверный логин/пароль).
    case server(SubsonicServerError)
    /// HTTP-код вне 2xx.
    case http(Int)
    /// Ответ не разобрался или пришёл без ожидаемой полезной нагрузки.
    case malformedResponse
    /// В настройках источника лежит адрес, из которого не собирается URL.
    case invalidServerURL
}

// MARK: - Сущности каталога

/// Артист из `getArtists` / `getArtist`.
public struct SubsonicArtist: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let albumCount: Int?
}

/// Альбом из `getAlbumList2` / `getAlbum`.
public struct SubsonicAlbum: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let artist: String?
    public let artistId: String?
    public let coverArt: String?
    public let songCount: Int?
    public let duration: Int?
    public let year: Int?
}

/// Трек из `getAlbum`. Поля `samplingRate`/`bitDepth`/`channelCount` —
/// расширение OpenSubsonic: старый Subsonic их не присылает, тогда истинный
/// формат становится известен только после скачивания файла (SPEC §6.2).
public struct SubsonicSong: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let album: String?
    public let artist: String?
    public let albumId: String?
    public let artistId: String?
    public let coverArt: String?
    public let track: Int?
    public let discNumber: Int?
    public let year: Int?
    public let duration: Int?
    public let size: Int64?
    public let suffix: String?
    public let contentType: String?
    public let bitRate: Int?
    public let samplingRate: Int?
    public let bitDepth: Int?
    public let channelCount: Int?
}

/// Альбом вместе с треками — то, что отдаёт `getAlbum`.
public struct SubsonicAlbumDetail: Sendable, Equatable {
    public let album: SubsonicAlbum
    public let songs: [SubsonicSong]
}

// MARK: - Полезные нагрузки эндпоинтов

/// `ping` не несёт ничего, кроме status/version.
struct EmptyPayload: Decodable, Sendable {}

/// `getArtists`: индексы по алфавиту, внутри каждого — артисты.
struct ArtistsPayload: Decodable, Sendable {
    let artists: Index

    struct Index: Decodable, Sendable {
        let index: [Letter]?
    }

    struct Letter: Decodable, Sendable {
        let name: String
        let artist: [SubsonicArtist]?
    }

    var flattened: [SubsonicArtist] {
        (artists.index ?? []).flatMap { $0.artist ?? [] }
    }
}

/// `getAlbumList2`: плоский список альбомов страницей.
struct AlbumListPayload: Decodable, Sendable {
    let albumList2: List

    struct List: Decodable, Sendable {
        let album: [SubsonicAlbum]?
    }
}

/// `getAlbum`: альбом с треками. Треки лежат в том же объекте под `song`.
struct AlbumPayload: Decodable, Sendable {
    let album: AlbumWithSongs

    struct AlbumWithSongs: Decodable, Sendable {
        let album: SubsonicAlbum
        let song: [SubsonicSong]?

        init(from decoder: Decoder) throws {
            album = try SubsonicAlbum(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            song = try container.decodeIfPresent([SubsonicSong].self, forKey: .song)
        }

        private enum CodingKeys: String, CodingKey {
            case song
        }
    }
}

/// `getArtist`: артист со своими альбомами.
struct ArtistPayload: Decodable, Sendable {
    let artist: ArtistWithAlbums

    struct ArtistWithAlbums: Decodable, Sendable {
        let artist: SubsonicArtist
        let album: [SubsonicAlbum]?

        init(from decoder: Decoder) throws {
            artist = try SubsonicArtist(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            album = try container.decodeIfPresent([SubsonicAlbum].self, forKey: .album)
        }

        private enum CodingKeys: String, CodingKey {
            case album
        }
    }
}
