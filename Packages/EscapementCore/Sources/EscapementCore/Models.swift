import Foundation

/// Domain models mirroring the DB schema in SPEC §5.1.
/// Pure values — no persistence logic here; GRDB conformances live in MusicLibrary.

public enum SourceKind: String, Codable, Sendable {
    case local
    case subsonic
}

public struct Source: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: SourceKind
    public var displayName: String
    public var bookmark: Data?
    public var serverUrl: String?
    public var username: String?
    public var enabled: Bool
    public var lastScanAt: Date?

    public init(
        id: String = UUID().uuidString,
        kind: SourceKind,
        displayName: String,
        bookmark: Data? = nil,
        serverUrl: String? = nil,
        username: String? = nil,
        enabled: Bool = true,
        lastScanAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bookmark = bookmark
        self.serverUrl = serverUrl
        self.username = username
        self.enabled = enabled
        self.lastScanAt = lastScanAt
    }
}

public struct Artist: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var name: String
    public var sortName: String
    public var mbid: String?

    public init(id: Int64? = nil, name: String, sortName: String, mbid: String? = nil) {
        self.id = id
        self.name = name
        self.sortName = sortName
        self.mbid = mbid
    }
}

public struct Album: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var title: String
    public var sortTitle: String
    public var artistId: Int64?
    public var albumArtist: String?
    public var year: Int?
    public var date: String?
    public var mbid: String?
    public var discCount: Int?
    public var coverHash: String?
    public var isCompilation: Bool

    public init(
        id: Int64? = nil,
        title: String,
        sortTitle: String,
        artistId: Int64? = nil,
        albumArtist: String? = nil,
        year: Int? = nil,
        date: String? = nil,
        mbid: String? = nil,
        discCount: Int? = nil,
        coverHash: String? = nil,
        isCompilation: Bool = false
    ) {
        self.id = id
        self.title = title
        self.sortTitle = sortTitle
        self.artistId = artistId
        self.albumArtist = albumArtist
        self.year = year
        self.date = date
        self.mbid = mbid
        self.discCount = discCount
        self.coverHash = coverHash
        self.isCompilation = isCompilation
    }
}

public struct Track: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var sourceId: String
    public var remoteId: String?
    public var relativePath: String?
    public var fileSize: Int64?
    public var modifiedAt: Date?
    public var title: String
    public var artistId: Int64?
    public var albumId: Int64?
    public var trackNo: Int?
    public var discNo: Int?
    public var duration: Double
    public var codec: String
    public var sampleRate: Int
    public var bitDepth: Int?
    public var channels: Int
    public var bitrate: Int?
    public var replaygainTrack: Double?
    public var replaygainAlbum: Double?
    public var addedAt: Date

    public init(
        id: Int64? = nil,
        sourceId: String,
        remoteId: String? = nil,
        relativePath: String? = nil,
        fileSize: Int64? = nil,
        modifiedAt: Date? = nil,
        title: String,
        artistId: Int64? = nil,
        albumId: Int64? = nil,
        trackNo: Int? = nil,
        discNo: Int? = nil,
        duration: Double,
        codec: String,
        sampleRate: Int,
        bitDepth: Int? = nil,
        channels: Int = 2,
        bitrate: Int? = nil,
        replaygainTrack: Double? = nil,
        replaygainAlbum: Double? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.sourceId = sourceId
        self.remoteId = remoteId
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.title = title
        self.artistId = artistId
        self.albumId = albumId
        self.trackNo = trackNo
        self.discNo = discNo
        self.duration = duration
        self.codec = codec
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.bitrate = bitrate
        self.replaygainTrack = replaygainTrack
        self.replaygainAlbum = replaygainAlbum
        self.addedAt = addedAt
    }
}

public struct Playlist: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isSmart: Bool
    public var rulesJson: String?

    public init(
        id: Int64? = nil,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isSmart: Bool = false,
        rulesJson: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isSmart = isSmart
        self.rulesJson = rulesJson
    }
}

public struct PlaylistItem: Codable, Sendable, Equatable {
    public var playlistId: Int64
    public var trackId: Int64
    public var position: Int

    public init(playlistId: Int64, trackId: Int64, position: Int) {
        self.playlistId = playlistId
        self.trackId = trackId
        self.position = position
    }
}

public struct PlayHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var trackId: Int64
    public var playedAt: Date
    public var completed: Bool
    public var durationPlayed: Double

    public init(
        id: Int64? = nil,
        trackId: Int64,
        playedAt: Date = Date(),
        completed: Bool,
        durationPlayed: Double
    ) {
        self.id = id
        self.trackId = trackId
        self.playedAt = playedAt
        self.completed = completed
        self.durationPlayed = durationPlayed
    }
}
