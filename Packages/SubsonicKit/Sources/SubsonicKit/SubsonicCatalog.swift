import EscapementCore
import Foundation

/// Перевод каталога сервера в доменные записи библиотеки (фаза 6, pack 3).
///
/// Чистые функции: сеть уже отработала, БД ещё не тронута — поэтому всё здесь
/// проверяется тестами на записанных ответах Navidrome.
public enum SubsonicCatalog {

    /// Трек сервера в доменный `Track`. `remote_id` — единственный ключ,
    /// по которому строка потом узнаётся: путей у сервера нет.
    ///
    /// Формат бывает известен не полностью: `samplingRate`/`bitDepth`/
    /// `channelCount` — расширение OpenSubsonic, старый сервер их не шлёт.
    /// Тогда пишем то, что известно наверняка, и не выдумываем: истинный
    /// формат станет виден после скачивания (SPEC §6.2).
    public static func track(
        from song: SubsonicSong, sourceId: String, artistId: Int64?, albumId: Int64?,
        addedAt: Date = Date()
    ) -> Track {
        Track(
            sourceId: sourceId,
            remoteId: song.id,
            title: nonEmpty(song.title) ?? "Untitled",
            artistId: artistId,
            albumId: albumId,
            trackNo: song.track,
            discNo: song.discNumber,
            duration: Double(song.duration ?? 0),
            codec: codec(for: song),
            // 0 — «неизвестно»: badge покажет реальную частоту, когда файл
            // приедет. Врать 44100 нельзя, на этом строится весь §4.
            sampleRate: song.samplingRate ?? 0,
            bitDepth: song.bitDepth,
            channels: song.channelCount ?? 2,
            bitrate: song.bitRate,
            addedAt: addedAt)
    }

    /// Альбом сервера в доменный `Album`.
    public static func album(
        from album: SubsonicAlbum, artistId: Int64?
    ) -> Album {
        let title = nonEmpty(album.name) ?? "Untitled Album"
        return Album(
            title: title,
            sortTitle: Normalize.sortName(for: title),
            artistId: artistId,
            albumArtist: nonEmpty(album.artist),
            year: album.year)
    }

    /// Кодек из того, что прислал сервер: `suffix` («flac») честнее
    /// `contentType` («audio/flac»), но берём что есть.
    public static func codec(for song: SubsonicSong) -> String {
        if let suffix = nonEmpty(song.suffix) { return suffix.lowercased() }
        if let type = nonEmpty(song.contentType), let slash = type.firstIndex(of: "/") {
            return String(type[type.index(after: slash)...]).lowercased()
        }
        return "unknown"
    }

    /// Что делать с локальной копией каталога после ответа сервера: сервер —
    /// источник правды, поэтому исчезнувшее у него исчезает и здесь.
    public static func diff(
        remoteIds: [String], localIds: [String]
    ) -> (added: [String], removed: [String]) {
        let remote = Set(remoteIds)
        let local = Set(localIds)
        return (
            added: remoteIds.filter { !local.contains($0) },
            removed: localIds.filter { !remote.contains($0) }
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
