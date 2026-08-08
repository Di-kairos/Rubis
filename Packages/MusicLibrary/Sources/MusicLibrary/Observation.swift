import EscapementCore
import Foundation
import GRDB

/// ValueObservation wrappers (SPEC §10): DB changes arrive as AsyncSequences
/// delivered on the main actor for direct consumption by @Observable view models.
public enum LibraryObservation {
    /// Emits the full album list whenever the album table changes.
    /// Albums without tracks are hidden: a scan can leave an empty album row
    /// behind (e.g. metadata-only folder) — showing an anonymous tile confuses.
    /// `sourceId` narrows the list to albums that have tracks from that source
    /// (sidebar source click, session 05: sources act as music directions).
    public static func albums(db: any DatabaseAccess, sourceId: String? = nil)
        -> AsyncValueObservation<[Album]>
    {
        ValueObservation
            .tracking { database in
                let request: QueryInterfaceRequest<Album>
                if let sourceId {
                    request = Album.filter(
                        sql: """
                            EXISTS (SELECT 1 FROM track \
                            WHERE track.album_id = album.id AND track.source_id = ?)
                            """,
                        arguments: [sourceId])
                } else {
                    request = Album.filter(
                        sql: "EXISTS (SELECT 1 FROM track WHERE track.album_id = album.id)")
                }
                return try request.order(Column("sort_title")).fetchAll(database)
            }
            .values(in: db.reader, scheduling: .mainActor)
    }

    /// Emits tracks of one album whenever they change.
    public static func tracks(inAlbum albumId: Int64, db: any DatabaseAccess)
        -> AsyncValueObservation<[Track]>
    {
        ValueObservation
            .tracking {
                try Track
                    .filter(Column("album_id") == albumId)
                    .order(Column("disc_no").ascNullsLast, Column("track_no").ascNullsLast)
                    .fetchAll($0)
            }
            .values(in: db.reader, scheduling: .mainActor)
    }

    /// Emits the playlist list whenever playlists change.
    public static func playlists(db: any DatabaseAccess)
        -> AsyncValueObservation<[Playlist]>
    {
        ValueObservation
            .tracking { try Playlist.order(Column("name")).fetchAll($0) }
            .values(in: db.reader, scheduling: .mainActor)
    }
}
