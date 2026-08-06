import EscapementCore
import Foundation
import SFBAudioEngine

/// Everything the scanner needs from one audio file, already mapped
/// by the SPEC §5.3 priority rules.
public struct FileMetadata: Sendable {
    public let title: String
    public let artist: String?
    public let albumTitle: String?
    public let albumArtistTag: String?
    public let artistSortTag: String?
    public let albumSortTag: String?
    public let isCompilationTagged: Bool
    public let trackNo: Int?
    public let discNo: Int
    public let year: Int?
    public let date: String?
    public let duration: Double
    public let codec: String
    public let sampleRate: Int
    public let bitDepth: Int?
    public let channels: Int
    public let bitrate: Int?
    public let replaygainTrack: Double?
    public let replaygainAlbum: Double?
    public let embeddedCover: Data?
}

public enum MetadataReader {
    /// Reads tags and stream properties (SPEC §5.3). Throws on unreadable files —
    /// the scanner turns that into a Problem-files entry, never a crash.
    public static func read(url: URL) throws -> FileMetadata {
        let file = try AudioFile(readingPropertiesAndMetadataFrom: url)
        let metadata = file.metadata
        let properties = file.properties

        let title = metadata.title ?? url.deletingPathExtension().lastPathComponent
        let discNo = metadata.discNumber ?? 1
        let releaseDate = metadata.releaseDate
        // year из полной даты (ISO) или из голого года в теге
        let year = releaseDate.flatMap { Int($0.prefix(4)) }

        return FileMetadata(
            title: title,
            artist: metadata.artist,
            albumTitle: metadata.albumTitle,
            albumArtistTag: metadata.albumArtist,
            artistSortTag: metadata.artistSortOrder,
            albumSortTag: metadata.albumTitleSortOrder,
            isCompilationTagged: metadata.isCompilation ?? false,
            trackNo: metadata.trackNumber,
            discNo: discNo,
            year: year,
            date: releaseDate,
            duration: properties.duration ?? 0,
            codec: url.pathExtension.lowercased(),
            sampleRate: Int(properties.sampleRate ?? 0),
            bitDepth: properties.bitDepth,
            channels: properties.channelCount.map(Int.init) ?? 2,
            bitrate: properties.bitrate.map(Int.init),
            replaygainTrack: metadata.replayGainTrackGain,
            replaygainAlbum: metadata.replayGainAlbumGain,
            embeddedCover: metadata.attachedPictures.first?.imageData)
    }
}
